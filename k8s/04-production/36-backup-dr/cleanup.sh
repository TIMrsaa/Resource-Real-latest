#!/usr/bin/env bash
# 모듈 36 정리 — Velero, shop ns, S3/IAM (비용 나가는 것부터)
set -euo pipefail
export AWS_REGION=ap-northeast-2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET=velero-backup-$ACCOUNT_ID

# 스케줄/백업 삭제 (S3 객체 + EBS 스냅샷이 함께 정리됨 — 비용 포인트)
velero schedule delete shop-daily --confirm 2>/dev/null || true
for b in $(velero backup get -o name 2>/dev/null); do velero backup delete "${b#backup/}" --confirm; done
sleep 20    # 백업 삭제(스냅샷 정리) 전파 대기

kubectl delete namespace shop --ignore-not-found
velero uninstall --force 2>/dev/null || kubectl delete namespace velero --ignore-not-found

# Pod Identity association / IAM / S3
eksctl delete podidentityassociation --cluster k8s-study --region $AWS_REGION \
  --namespace velero --service-account-name velero 2>/dev/null || true
aws iam delete-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/VeleroLab 2>/dev/null || true
aws s3 rb s3://$BUCKET --force 2>/dev/null || true

# 남은 EBS 스냅샷 확인 (있으면 수동 삭제 — 과금 대상)
aws ec2 describe-snapshots --owner-ids self --region $AWS_REGION \
  --filters "Name=tag-key,Values=velero.io/backup" \
  --query 'Snapshots[].SnapshotId' --output text
rm -f velero-policy.json
echo "모듈 36 정리 완료 (위에 스냅샷 ID가 출력됐다면 aws ec2 delete-snapshot으로 삭제)"
