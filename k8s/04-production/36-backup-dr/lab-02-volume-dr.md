# Lab 02 — 데이터까지, 자동으로, 그리고 설계로

lab-01은 "형태"(리소스)를 살렸습니다. 이번엔 **디스크 위 데이터**를 살리고, 백업을 스케줄로 자동화하고, 마지막으로 DR을 숫자로 설계합니다.

## Step 1. 잃으면 안 되는 데이터 만들기 (PVC)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: shop }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3                    # 08의 StorageClass
  resources: { requests: { storage: 1Gi } }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: keeper, namespace: shop }
spec:
  replicas: 1
  strategy: { type: Recreate }             # RWO 볼륨 — 07의 그 이유
  selector: { matchLabels: { app: keeper } }
  template:
    metadata:
      labels: { app: keeper }
    spec:
      volumes: [{ name: data, persistentVolumeClaim: { claimName: data } }]
      containers:
      - name: app
        image: public.ecr.aws/docker/library/busybox:stable
        command: [sleep, "3600"]
        volumeMounts: [{ name: data, mountPath: /data }]
EOF
kubectl wait --for=condition=Ready pod -l app=keeper -n shop --timeout=120s
kubectl exec -n shop deploy/keeper -- sh -c 'echo "precious data 2026" > /data/important.txt'
kubectl exec -n shop deploy/keeper -- cat /data/important.txt
```

## Step 2. 볼륨 포함 백업 — 스냅샷이 함께 찍힙니다

```bash
velero backup create shop-with-data --include-namespaces shop --wait
velero backup describe shop-with-data --details | grep -iA4 "snapshot\|volume"

# AWS 쪽 물증 — Velero가 태그를 달아 만든 EBS 스냅샷
aws ec2 describe-snapshots --owner-ids self --region ap-northeast-2 \
  --filters "Name=tag:velero.io/backup,Values=shop-with-data" \
  --query 'Snapshots[].{id:SnapshotId,state:State,size:VolumeSize}' --output table
```

✅ 리소스는 S3로, 볼륨은 EBS 스냅샷으로 — theory §3의 분업이 눈에 보입니다. (파일 백업 모드를 쓰려면 Pod에 `backup.velero.io/backup-volumes: data` annotation — 리전·클라우드를 넘는 이식성이 필요할 때)

## Step 3. 데이터 소실 → 완전 복구

```bash
kubectl delete namespace shop                 # PVC까지 함께 소멸 (EBS 볼륨도 삭제됨!)
velero restore create data-restore --from-backup shop-with-data --wait
kubectl wait --for=condition=Ready pod -l app=keeper -n shop --timeout=180s
kubectl exec -n shop deploy/keeper -- cat /data/important.txt
```

예상 출력:

```
precious data 2026
```

✅ 스냅샷에서 **새 EBS 볼륨이 복원**되어 PVC에 바인딩됐습니다 — 형태(lab-01)에 이어 **내용물까지** 살아나는 완전한 사이클. 원본 볼륨이 삭제된 뒤였다는 점이 핵심입니다.

## Step 4. 자동화 — Schedule (20의 cron이 백업 공장이 됩니다)

```bash
velero schedule create shop-daily \
  --schedule="0 2 * * *" \
  --include-namespaces shop \
  --ttl 168h                                  # 7일 지난 백업 자동 삭제 — S3 비용 제어
velero schedule get

# 스케줄 검증은 새벽까지 기다리지 않습니다 — 즉시 1회 트리거 (20의 create --from 패턴)
velero backup create --from-schedule shop-daily
velero backup get | head -5
```

✅ 이 스케줄의 의미를 숫자로 읽으면: **RPO = 최대 24시간** (새벽 2시 직전 사고 시 하루치 손실). 이 값이 서비스 요구와 맞는지가 Step 5의 질문입니다.

## Step 5. DR 워크시트 — 이 모듈의 산출물

가상 서비스 3개에 티어를 매깁니다. 빈 칸을 채워보세요 (아래는 답안 예):

```markdown
# DR 티어링 워크시트
| 서비스 | 사고 시 잃어도 되는 데이터(RPO) | 견딜 수 있는 다운타임(RTO) | 전략 | 백업 주기 |
|--------|------------------------------|--------------------------|------|----------|
| 결제   | 사실상 0                      | <5분                     | 웜 스탠바이~액티브-액티브 + 실시간 복제 | (백업으론 불충분) |
| 주문   | <1시간                        | <30분                    | 파일럿 라이트 + Velero 시간별 | 1h |
| 분석   | 24시간 (재집계 가능)           | <4시간                   | Velero 일일 (Step 4의 그것) | 24h |

# 재해 시 복구 순서 (의존성 역순)
1. 결제 → 2. 주문 → 3. 분석
# 근거 없는 칸 금지 — RTO 계획값 옆에는 lab-01 Step 7 같은 실측값을
```

✅ 세 서비스가 **서로 다른 DR**을 받는다는 것이 답의 전부입니다. 하나의 전략을 전사에 씌우는 순간 어딘가는 도박, 어딘가는 낭비가 됩니다.

## Step 6. Game Day — 방금 한 것을 제도로

돌아보면 Step 3이 이미 복구 훈련이었습니다. 남은 건 기록과 반복:

```markdown
# 복구 훈련 기록 (분기 반복)
- 대상: shop ns (볼륨 포함) / 백업: shop-with-data
- RTO 실측: restore Started~Completed + Pod Ready까지 = __분 (계획 대비?)
- RPO 검증: important.txt 내용이 백업 시점과 일치 ○
- 막힌 곳: (기록할 것 — 권한? BSL? 절차?)
- runbook 반영: __
```

## 정리

```bash
bash cleanup.sh     # 스케줄→백업(스냅샷 정리 동반)→ns→Velero→IAM/S3 순서 — 과금 잔재 확인까지
```
