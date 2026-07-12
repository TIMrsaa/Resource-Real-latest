# Lab 01 — 격리 백업: 사다리 두 번째 칸 오르기

백업을 **다른 리전**에 두는 것을 실제로 구성합니다 — Velero의 다중 BSL로. (36의 Velero 설치가 정리된 상태라면 Step 1로 재설치 — 명령은 36 lab-01의 요약판)

```bash
export AWS_REGION=ap-northeast-2          # 주 리전 (서울)
export DR_REGION=ap-northeast-1           # 격리 리전 (도쿄)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. Velero 재설치 (36의 절차 압축 — 이미 있으면 건너뜀)

```bash
aws s3 mb s3://velero-backup-$ACCOUNT_ID --region $AWS_REGION 2>/dev/null || true
# IAM 정책/Pod Identity association: 36 lab-01 Step 1~2와 동일 (policy VeleroLab)
velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket velero-backup-$ACCOUNT_ID --backup-location-config region=$AWS_REGION \
  --snapshot-location-config region=$AWS_REGION --use-volume-snapshots=true \
  --no-secret --service-account-name velero
kubectl rollout status deploy/velero -n velero --timeout=120s
```

## Step 2. 격리 리전의 금고 — 두 번째 버킷과 BSL

```bash
aws s3 mb s3://velero-dr-$ACCOUNT_ID --region $DR_REGION

# 두 번째 BackupStorageLocation — "도쿄 금고"
velero backup-location create dr-tokyo \
  --provider aws --bucket velero-dr-$ACCOUNT_ID \
  --config region=$DR_REGION
velero backup-location get
```

예상: `default`(서울)와 `dr-tokyo` 둘 다 **Available** — Velero는 금고를 여러 개 가질 수 있고, 백업마다 행선지를 고릅니다.

## Step 3. 행선지를 나눠 백업

```bash
# 지킬 대상 (간단 세트)
kubectl create ns dr-target
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: dr-target
  labels: { app: app }
spec:
  replicas: 1
  selector:
    matchLabels: { app: app }
  template:
    metadata:
      labels: { app: app }
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
EOF
kubectl create secret generic keys -n dr-target --from-literal=api=dr-drill-2026

# 일상 백업 → 서울 (기본 BSL)
velero backup create daily-local --include-namespaces dr-target --wait
# DR 백업 → 도쿄 (격리 BSL)
velero backup create dr-copy --include-namespaces dr-target --storage-location dr-tokyo --wait

# 물증 — 도쿄 리전 버킷에 실물이 있는가
aws s3 ls s3://velero-dr-$ACCOUNT_ID/backups/dr-copy/ --region $DR_REGION
```

✅ **서울 리전이 통째로 사라져도 dr-copy는 삽니다** — 사다리 두 번째 칸. 이 백업이 lab-02 재건의 4층 재료입니다.

## Step 4. 위 칸들 — 구현은 버킷의 일 (설계 확인)

```bash
# 세 번째 칸(타계정)·네 번째 칸(불변)은 S3 쪽 설정입니다 — 명령 형태만 확인:
# 타계정 복제: aws s3api put-bucket-replication (목적지 = 다른 계정의 버킷 + 소유권 이전)
# 오브젝트 잠금: 버킷 생성 시 --object-lock-enabled-for-bucket
#   → aws s3api put-object-lock-configuration (COMPLIANCE 모드 = 누구도 기간 내 삭제 불가)
```

책임 분계를 기록해두라: Velero는 "어느 금고에 넣을지"까지, 금고 자체의 요새화(복제·잠금)는 S3의 일 — 이 분리 덕에 백업 도구를 바꿔도 격리 설계가 삽니다.

## Step 5. 스케줄의 이중화 (산출물)

```markdown
# 백업 행선지 정책
- 일상(RPO 24h, 빠른 복구용): schedule daily → default(서울) — TTL 7일
- DR(리전 생존용): schedule dr-weekly → dr-tokyo — TTL 30일
  velero schedule create dr-weekly --schedule="0 3 * * 0" \
    --storage-location dr-tokyo --ttl 720h
- 위협 모델 대비 현재 높이: [x] 타리전  [ ] 타계정(분기 내)  [ ] Object Lock(보안 리뷰 후)
- 감시(36 pitfall 5): 두 스케줄 각각의 "마지막 성공 나이" 알람
```

## 정리

dr-target ns와 백업은 lab-02의 재료 — 유지합니다.
