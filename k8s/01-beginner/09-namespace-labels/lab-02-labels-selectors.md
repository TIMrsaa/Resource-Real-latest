# Lab 02 — Label/Selector 문법 집중 훈련

## Step 0. 훈련용 Pod 6개 깔기

```bash
for env in dev staging prod; do
  for tier in front back; do
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pod-$env-$tier
  labels:
    env: $env
    tier: $tier
spec:
  containers:
    - name: main
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "3600"]
EOF
  done
done
kubectl get pods --show-labels | grep pod-
```

## Step 1. 등호 셀렉터

```bash
kubectl get pods -l env=prod                       # prod 2개
kubectl get pods -l env=prod,tier=front            # AND → 1개
kubectl get pods -l env!=prod                      # 4개
```

각 명령 전에 몇 개가 나올지 **먼저 예상하고** 실행하세요.

## Step 2. 집합 셀렉터

```bash
kubectl get pods -l 'env in (dev,staging)'              # 4개
kubectl get pods -l 'env notin (prod),tier=back'        # 2개
kubectl get pods -l 'env'                               # env 키 있는 전부 → 6개
kubectl get pods -l '!canary'                           # canary 키 없는 전부 → 6개
```

## Step 3. 라벨 동적 조작

```bash
kubectl label pod pod-prod-front canary=true            # 추가
kubectl get pods -l canary=true
kubectl label pod pod-prod-front canary=false --overwrite   # 변경 (--overwrite 필수)
kubectl label pod pod-prod-front canary-                 # 제거 (key 뒤 마이너스)
```

## Step 4. 일괄 작업에 셀렉터 활용 — 라벨의 진짜 힘

```bash
# dev 환경만 통째로 삭제
kubectl delete pods -l env=dev
# 남은 것 확인
kubectl get pods -l 'env in (staging,prod)' --no-headers | wc -l    # → 4
```

> 💡 실무 패턴: `kubectl rollout restart deploy -l team=checkout` (팀 서비스 일괄 재시작), `kubectl get pods -A -l app.kubernetes.io/managed-by=Helm` (Helm 관리분만 조회) — 라벨 설계가 곧 운영 명령의 어휘가 됩니다.

## Step 5. field selector와의 구분

```bash
# label이 아니라 "리소스 필드"로 거르기
kubectl get pods -A --field-selector status.phase=Running | head -5
kubectl get pods -A --field-selector spec.nodeName=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}') | head -5
```

- label selector: 사용자가 붙인 메타데이터 기준 (인덱싱돼 빠름, 표현력 큼)
- field selector: 시스템 필드 기준 (지원 필드 제한적: metadata.name/namespace, status.phase, spec.nodeName 등)

## Step 6. annotation은 selector가 안 됩니다 (확인 사살)

```bash
kubectl annotate pod pod-prod-back note="중요한 메모"
kubectl get pods -l note=중요한 메모 2>&1 | head -1     # 라벨로는 못 찾음 (빈 결과/에러)
kubectl get pod pod-prod-back -o jsonpath='{.metadata.annotations.note}'; echo   # 직접 조회만 가능
```

## 정리

```bash
bash cleanup.sh
```
