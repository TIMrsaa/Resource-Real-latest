#!/usr/bin/env bash
# 모듈 10 정리 — EFS/EBS/스냅샷 (전부 과금원!)
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}

kubectl delete namespace storage-lab --ignore-not-found
kubectl delete storageclass gp3-x efs-ap --ignore-not-found
kubectl delete volumesnapshotclass ebs-snap --ignore-not-found 2>/dev/null || true
sleep 20

# EFS (mount target → filesystem 순)
FS_ID=$(aws efs describe-file-systems --region "$AWS_REGION" \
  --query 'FileSystems[?Tags[?Key==`Name`&&Value==`eks-lab`]].FileSystemId' --output text)
if [ -n "$FS_ID" ] && [ "$FS_ID" != "None" ]; then
  for MT in $(aws efs describe-mount-targets --file-system-id "$FS_ID" --region "$AWS_REGION" \
    --query 'MountTargets[].MountTargetId' --output text); do
    aws efs delete-mount-target --mount-target-id "$MT" --region "$AWS_REGION"
  done
  sleep 60
  aws efs delete-file-system --file-system-id "$FS_ID" --region "$AWS_REGION"
  echo "EFS $FS_ID 삭제"
fi

# 잔존 확인 (EBS 볼륨/스냅샷)
aws ec2 describe-volumes --region "$AWS_REGION" --filters "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' --output text
aws ec2 describe-snapshots --owner-ids self --region "$AWS_REGION" --query 'length(Snapshots)'
echo "모듈 10 정리 완료 — 위에 잔존 볼륨/스냅샷 수가 있으면 확인 후 수동 삭제"
