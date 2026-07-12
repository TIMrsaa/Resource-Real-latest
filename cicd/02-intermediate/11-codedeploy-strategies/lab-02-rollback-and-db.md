# Lab 02 — 자동 롤백과 expand-contract 마이그레이션

배포의 안전은 "되돌릴 수 있음"에서 옵니다. 자동 롤백이 무엇을 관찰하는지 보고, 되돌릴 수 없는 것(DB 스키마)을 안전하게 다루는 패턴을 실습합니다.

전제: lab-01의 deploylab.

## Step 1. 롤백의 전제 — 관찰 지표를 먼저

자동 롤백은 "무엇을 보고 되돌릴지"가 없으면 불가능합니다(theory §3). 나쁜 버전을 배포해봅니다:

```bash
# v3: 50% 확률로 500을 뱉는 "나쁜 버전"
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-v3, namespace: deploylab }
spec:
  replicas: 0
  selector: { matchLabels: { app: myapp, version: v3 } }
  template:
    metadata: { labels: { app: myapp, version: v3 } }
    spec:
      containers:
      - name: app
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        command: ["./podinfo", "--port=9898", "--random-error=true"]
        ports: [{ containerPort: 9898 }]
EOF
```

## Step 2. 카나리 + 관찰 = 게이트

v3를 5%로 내보내고 **오류율을 관찰**합니다 — 이 관찰이 롤백 결정의 근거입니다:

```bash
kubectl -n deploylab patch service app -p '{"spec":{"selector":{"app":"myapp"}}}'  # 버전 무관 선택
kubectl -n deploylab scale deploy app-v2 --replicas=19
kubectl -n deploylab scale deploy app-v3 --replicas=1     # 5% 카나리
kubectl -n deploylab rollout status deploy/app-v3

# 관찰: 카나리(v3)로 간 요청의 오류율 (이것이 게이트의 입력)
kubectl run probe -n deploylab --rm -i --restart=Never --image=curlimages/curl -- sh -c \
  'ok=0; err=0; for i in $(seq 1 100); do c=$(curl -s -o /dev/null -w "%{http_code}" http://app/); [ "$c" = "200" ] && ok=$((ok+1)) || err=$((err+1)); done; echo "성공 $ok / 실패 $err"'
```

예상: 약 2~3%의 실패(전체의 5%가 v3, 그 v3의 절반이 실패). ✅ **이 실패율이 감지되면 롤백 트리거**입니다. 실전에서는 이 관찰을 CloudWatch 알람(eks 12)이나 Prometheus(eks 15)가 자동 수행하고, CodeDeploy/Rollouts가 롤백을 실행합니다.

## Step 3. 롤백 — 가중치 0으로 (초 단위)

```bash
echo "🚨 카나리 오류율 초과 감지 → 자동 롤백"
kubectl -n deploylab scale deploy app-v3 --replicas=0     # 카나리 철수 = 롤백
kubectl run probe -n deploylab --rm -i --restart=Never --image=curlimages/curl -- sh -c \
  'ok=0; err=0; for i in $(seq 1 50); do c=$(curl -s -o /dev/null -w "%{http_code}" http://app/); [ "$c" = "200" ] && ok=$((ok+1)) || err=$((err+1)); done; echo "롤백 후: 성공 $ok / 실패 $err"'
```

예상: 실패 0 — v3가 트래픽에서 빠졌습니다. ✅ **카나리 롤백은 가중치 0으로, 초 단위**(theory §3). 구버전(v2)이 이미 떠 있으니 재배포가 필요 없습니다. 이것이 "블루/그린·카나리의 롤백이 롤링보다 빠른" 이유.

## Step 4. CodeDeploy 자동 롤백 구성 (개념)

ECS/Lambda라면 이 관찰-롤백이 선언적입니다:

```json
{
  "deploymentConfigName": "CodeDeployDefault.ECSCanary10Percent5Minutes",
  "autoRollbackConfiguration": {
    "enabled": true,
    "events": ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  },
  "alarmConfiguration": {
    "enabled": true,
    "alarms": [{ "name": "app-5xx-rate-high" }]   ← eks 12·14의 알람
  }
}
```

✅ "10% 내보내고 5분간 이 알람이 울리면 자동 롤백" — 우리가 손으로 한 관찰-판단-롤백이 구성 몇 줄로. **핵심은 여전히 알람(관찰 지표)이 정의돼 있어야** 한다는 것.

## Step 5. DB 마이그레이션 — 되돌릴 수 없는 것 (theory §5)

시뮬레이션: 앱 v2가 새 컬럼 `email_verified`를 요구합니다. **순진한 방법의 위험**을 먼저 보고, expand-contract로 고칩니다.

```bash
kubectl apply -f - 2>/dev/null <<'EOF' || true
apiVersion: v1
kind: Pod
metadata:
  name: pg
  namespace: deploylab
  labels: { app: pg }
spec:
  containers:
    - name: pg
      image: postgres:17
      env:
        - name: POSTGRES_PASSWORD
          value: test
      ports:
        - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: pg
  namespace: deploylab
spec:
  selector: { app: pg }
  ports:
    - port: 5432
EOF
kubectl -n deploylab wait --for=condition=Ready pod/pg --timeout=60s
PG="kubectl -n deploylab exec pg -- psql -U postgres -qtA"

$PG -c "CREATE TABLE users (id serial, name text);"
$PG -c "INSERT INTO users (name) VALUES ('alice'), ('bob');"
echo "--- 초기 스키마 (구버전 v1이 쓰는 것) ---"
$PG -c "\d users" 2>/dev/null | grep -E "name|email" || $PG -c "SELECT column_name FROM information_schema.columns WHERE table_name='users';"
```

### ❌ 순진한 방법의 문제 (개념)

```markdown
동시에: 코드 v2(email_verified 필요) + "ALTER TABLE ADD COLUMN NOT NULL"
→ 카나리 5%(v2)가 컬럼을 쓰는데, 롤백하면? 스키마는 이미 바뀜
→ 롤백한 구버전 95%가 새 제약(NOT NULL)에 걸려 INSERT 실패
= 코드는 롤백됐는데 시스템은 깨진 상태
```

### ✅ expand-contract

```bash
echo "=== 1. Expand: 하위 호환으로 컬럼 추가 (구버전도 무시하고 잘 돎) ==="
$PG -c "ALTER TABLE users ADD COLUMN email_verified boolean DEFAULT false;"   # NOT NULL 아님!
$PG -c "SELECT column_name FROM information_schema.columns WHERE table_name='users';"
echo "→ 구버전 v1: email_verified를 몰라도 INSERT 정상 (DEFAULT가 채움)"
$PG -c "INSERT INTO users (name) VALUES ('carol');" && echo "  구버전 스타일 INSERT 성공 ✓"

echo "=== 2. Migrate: 코드 v2 배포 (새 컬럼 씀, 카나리로 안전하게) ==="
echo "  → 이제 v2를 Step 2~3의 카나리로 점진 배포. 각 단계 롤백 가능(스키마가 하위 호환이니)"

echo "=== 3. Contract: v2 안정화 후, 구 방식 흔적 제거 ==="
echo "  → (예: 구 컬럼 제거, DEFAULT 정리) — v2만 남았을 때만"
$PG -c "ALTER TABLE users ALTER COLUMN email_verified SET NOT NULL;" && echo "  이제 NOT NULL 강제 가능 (모두 v2)"
```

✅ **각 단계가 독립적으로 롤백 가능**합니다 — expand 후 멈춰도, migrate 중 롤백해도 시스템이 동작합니다. 스키마 변경(되돌릴 수 없는 것)과 코드 배포(되돌릴 수 있는 것)를 **분리하고 각각 하위 호환**으로 만든 것. 02의 브랜치 바이 앱스트랙션과 같은 사상.

## Step 6. 산출물 — 배포 전략 결정 + 마이그레이션 규율

```markdown
# 서비스별 배포 전략
| 서비스 | 전략 | 롤백 지표 | DB 변경 시 |
|--------|------|----------|-----------|
| 결제 API | 카나리(5→25→50→100) | 5xx율, p99(eks 13) | expand-contract 필수 |
| 내부 도구 | 롤링 | 헬스체크 | 드물어서 수동 |
| 상태 저장 워커 | 블루/그린 | 큐 처리율 | expand-contract |

# 불변 규율
1. 카나리는 관찰 지표(SLI)가 정의됐을 때만 의미 있음 — 없으면 그냥 느린 배포
2. 자동 롤백 = 알람(eks 12) + 배포 구성. 알람 없이 자동 배포 금지(01)
3. DB 스키마 = expand-contract. 코드와 스키마를 절대 한 배포에 묶지 않음
4. 롤백 속도: 카나리/블루그린(초) 선호. 롤링은 재롤링(분)
5. k8s 진짜 카나리는 17(Argo Rollouts) — 이 랩의 수동 관찰을 자동화
```

## Step 7. 중급 진도

```markdown
09~11 → AWS Code 시리즈 (오케스트레이션·빌드·배포 전략)   [ ]
→ 12(GitLab CI), 13(Jenkins)로 생태계 조망 후 고급(14~)의 GitOps로
→ 11의 "관찰 후 확대"가 17(Progressive Delivery)에서 완전 자동화됩니다
```

## 정리

```bash
bash cleanup.sh
```
