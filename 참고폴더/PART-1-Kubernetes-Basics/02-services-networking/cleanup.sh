#!/usr/bin/env bash
set -euo pipefail

echo "▶ 모듈 02 리소스 정리"

# LoadBalancer 부터 삭제 (외부 LB 정리 시간 필요)
kubectl delete -f manifests/loadbalancer.yaml --ignore-not-found
kubectl delete -f manifests/nodeport.yaml --ignore-not-found
echo "  → NLB 삭제 진행 중 (30초 대기)..."
sleep 30

kubectl delete -f manifests/clusterip.yaml --ignore-not-found

echo "✅ 정리 완료"
echo ""
echo "AWS Console에서 NLB가 완전히 사라졌는지 확인 권장:"
echo "  aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'"
