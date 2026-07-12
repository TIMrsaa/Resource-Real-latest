#!/usr/bin/env bash
set -euo pipefail

echo "▶ 모듈 04 + 미니 프로젝트 리소스 정리"

# Helm release
helm uninstall order-service -n order 2>/dev/null || true
helm uninstall demo -n demo 2>/dev/null || true

kubectl delete ns order demo --ignore-not-found

# Imperative RBAC 정리
kubectl delete -f manifests/rbac.yaml --ignore-not-found
kubectl delete clusterrole node-reader --ignore-not-found
kubectl delete clusterrolebinding pod-reader-sa-node-reader --ignore-not-found

echo ""
echo "✅ 정리 완료"
echo ""
echo "Part 1 학습이 모두 끝났다면 EKS 클러스터 자체를 삭제하세요:"
echo "  eksctl delete cluster --name eks-study --region ap-northeast-2"
echo ""
echo "잔존 리소스 점검:"
echo "  bash ../../00-prerequisites/scripts/check-tools.sh   # 환경 점검"
echo "  aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text"
echo "  aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text"
