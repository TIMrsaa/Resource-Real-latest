#!/usr/bin/env bash
# 모듈 24 정리 — 백업/스케줄(스냅샷 동반) → Velero → 양 리전 버킷 → ns
set -euo pipefail
export AWS_REGION=ap-northeast-2
export DR_REGION=ap-northeast-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

velero schedule delete dr-weekly --confirm 2>/dev/null || true
for b in $(velero backup get -o name 2>/dev/null); do velero backup delete "${b#backup/}" --confirm; done
sleep 20

kubectl delete namespace dr-target --ignore-not-found
velero uninstall --force 2>/dev/null || kubectl delete namespace velero --ignore-not-found

eksctl delete podidentityassociation --cluster k8s-study --region $AWS_REGION \
  --namespace velero --service-account-name velero 2>/dev/null || true
aws iam delete-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/VeleroLab 2>/dev/null || true

aws s3 rb s3://velero-backup-$ACCOUNT_ID --force 2>/dev/null || true
aws s3 rb s3://velero-dr-$ACCOUNT_ID --force 2>/dev/null || true

# 잔여 EBS 스냅샷 확인 (과금!)
aws ec2 describe-snapshots --owner-ids self --region $AWS_REGION \
  --filters "Name=tag-key,Values=velero.io/backup" --query 'Snapshots[].SnapshotId' --output text
echo "모듈 24 정리 완료 (위에 스냅샷 ID 출력 시 수동 삭제)"
