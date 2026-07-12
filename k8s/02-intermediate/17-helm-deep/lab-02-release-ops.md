# Lab 02 — 릴리스 운영: upgrade, rollback, hooks, 의존성

> lab-01의 webapp-prod 릴리스(helm-prod ns)에서 이어갑니다. `cd ~/helm-lab/webapp`

## Step 1. upgrade와 history

```bash
helm upgrade webapp-prod . -f values-prod.yaml --set environment=prod-v2 --atomic
helm history webapp-prod -n helm-prod
```

예상 출력:
```
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         deployed    Upgrade complete
```

```bash
# 실제 반영 확인
kubectl get deploy -n helm-prod -o jsonpath='{.items[0].spec.template.spec.containers[0].env}' ; echo
```

## Step 2. 실패하는 upgrade와 --atomic의 가치

```bash
helm upgrade webapp-prod . -f values-prod.yaml \
  --set image.tag=no-such-tag --atomic --timeout 90s
```

예상 출력 (90초 후):
```
Error: UPGRADE FAILED: release webapp-prod failed, and has been rolled back due to atomic being set: timed out waiting for the condition
```

```bash
helm history webapp-prod -n helm-prod | tail -3
kubectl get pods -n helm-prod      # 멀쩡한 v2 Pod들만
```

예상: revision 3은 failed, **revision 4 = 자동 롤백** — 서비스는 한 번도 깨지지 않았습니다 (readiness probe가 새 Pod의 Ready를 막아준 것까지 합작 — 모듈 14).

## Step 3. 수동 rollback

```bash
helm rollback webapp-prod 1 -n helm-prod      # 첫 설치 상태로
helm get values webapp-prod -n helm-prod      # environment가 prod로 돌아옴
helm rollback webapp-prod 2 -n helm-prod      # 다시 v2로 (rollback도 새 revision)
```

> 💡 Helm 릴리스 기록의 실체 확인: `kubectl get secrets -n helm-prod | grep sh.helm` — revision마다 Secret 하나.

## Step 4. Hook — pre-upgrade 마이그레이션 Job

```bash
cat > templates/migrate-job.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "webapp.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migrate
        image: public.ecr.aws/docker/library/busybox:stable
        command: ["sh", "-c", "echo 'migrating database to {{ .Values.environment }}...'; sleep 5; echo done"]
EOF

helm upgrade webapp-prod . -f values-prod.yaml --atomic
kubectl get jobs -n helm-prod        # hook-succeeded 정책으로 이미 삭제됐을 수 있음
helm history webapp-prod -n helm-prod | tail -2
```

✅ upgrade 출력이 잠시 멈췄던 구간이 hook Job 실행 시간입니다. **마이그레이션 실패 = upgrade 실패 = (atomic) 자동 롤백** — 배포와 마이그레이션의 원자적 결합.

```bash
# 실패 시나리오도 검증 (sleep 5 → exit 1로 바꿔 upgrade 해보면 롤백되는 것 확인)
```

## Step 5. 의존성 — redis 붙이기

Chart.yaml에 추가:

```yaml
dependencies:
- name: redis
  version: "~21.x"
  repository: oci://registry-1.docker.io/bitnamicharts
  condition: redis.enabled
```

values-prod.yaml에 추가:
```yaml
redis:
  enabled: true
  architecture: standalone
  auth: { enabled: false }
```

```bash
helm dependency update          # charts/redis-*.tgz 다운로드
helm upgrade webapp-prod . -f values-prod.yaml --atomic --timeout 5m
kubectl get pods -n helm-prod
```

예상: `webapp-prod-redis-master-0` (StatefulSet — 다음 모듈 19의 예고편!)가 함께 떠 있습니다. 부모 values의 `redis:` 블록이 자식 차트로 전달된 것.

## Step 6. 패키징과 OCI 배포 (참고 절차)

```bash
helm package .                                  # webapp-0.1.0.tgz
# ECR에 차트 푸시 (이미지처럼!)
aws ecr create-repository --repository-name charts/webapp --region ap-northeast-2 2>/dev/null || true
aws ecr get-login-password --region ap-northeast-2 | helm registry login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-northeast-2.amazonaws.com
helm push webapp-0.1.0.tgz oci://$(aws sts get-caller-identity --query Account --output text).dkr.ecr.ap-northeast-2.amazonaws.com/charts
```

✅ 차트도 OCI 아티팩트입니다(모듈 01의 표준이 여기까지) — 팀 배포 채널이 ECR 하나로 통일됩니다.

## 정리

```bash
bash cleanup.sh
```
