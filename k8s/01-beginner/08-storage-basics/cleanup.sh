#!/usr/bin/env bash
# 모듈 08 정리 — PVC 삭제로 EBS까지 회수 (Delete 정책)
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}

kubectl delete deployment keeper --ignore-not-found
kubectl delete pod scratch hp-writer --ignore-not-found
kubectl delete pvc data --ignore-not-found
kubectl delete storageclass gp3 --ignore-not-found

echo "EBS 잔존 확인 (kubernetes.io 태그 볼륨):"
aws ec2 describe-volumes --region "$AWS_REGION" \
  --filters "Name=tag-key,Values=kubernetes.io/created-for/pvc/name" \
  --query 'Volumes[].{ID:VolumeId,State:State}' --output table 2>/dev/null || true
echo "모듈 08 정리 완료 (CSI 애드온은 이후 모듈에서 재사용하므로 유지)"
