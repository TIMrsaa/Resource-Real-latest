#!/usr/bin/env bash
# 모듈 19 정리 — PVC까지 명시 삭제 (EBS 비용!)
set -euo pipefail
kubectl delete pdb db-pdb --ignore-not-found
kubectl delete statefulset db --ignore-not-found
kubectl delete svc db --ignore-not-found
kubectl delete pod dnsutil --ignore-not-found
# StatefulSet 삭제로는 PVC가 안 지워집니다 — 직접!
kubectl delete pvc -l app=db --ignore-not-found
echo "EBS 잔존 확인:"
aws ec2 describe-volumes --region "${AWS_REGION:-ap-northeast-2}" \
  --filters "Name=tag-key,Values=kubernetes.io/created-for/pvc/name" \
  --query 'Volumes[].VolumeId' --output text 2>/dev/null || true
echo "모듈 19 정리 완료"
