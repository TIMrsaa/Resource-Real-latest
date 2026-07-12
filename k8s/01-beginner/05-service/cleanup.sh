#!/usr/bin/env bash
# 모듈 05 정리 — LB부터 지웁니다 (NLB 고아 방지)
set -euo pipefail
kubectl delete svc echo-lb --ignore-not-found     # NLB 삭제 유발
kubectl delete svc echo-np echo --ignore-not-found
kubectl delete deployment echo --ignore-not-found
kubectl delete pod client pinger np-test --ignore-not-found 2>/dev/null || true
echo "NLB 잔존 확인:"
aws elbv2 describe-load-balancers --region "${AWS_REGION:-ap-northeast-2}" \
  --query 'LoadBalancers[].LoadBalancerName' --output text 2>/dev/null || true
echo "모듈 05 정리 완료"
