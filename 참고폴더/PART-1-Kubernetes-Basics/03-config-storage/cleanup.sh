#!/usr/bin/env bash
set -euo pipefail

echo "▶ 모듈 03 리소스 정리"

kubectl delete -f manifests/redis-statefulset.yaml --ignore-not-found
kubectl delete pvc -l app=redis --ignore-not-found

kubectl delete -f manifests/pvc-pod.yaml --ignore-not-found
kubectl delete -f manifests/configmap-secret.yaml --ignore-not-found

# StorageClass는 다음 모듈에서도 쓰므로 유지 (기본값으로 두면 OK)
# kubectl delete -f manifests/storageclass-gp3.yaml

echo "  → EBS 볼륨 삭제 진행 중 (30초 대기)..."
sleep 30

echo ""
echo "잔존 EBS 볼륨 확인:"
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/cluster/eks-study,Values=owned" Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size,CreateTime]' --output table

echo ""
echo "✅ 정리 완료. 위 결과가 비어있어야 합니다."
