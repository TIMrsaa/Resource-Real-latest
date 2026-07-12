#!/usr/bin/env bash
# 모듈 14 정리 — Ingress(=ALB) 삭제가 핵심. 소멸 확인까지.
set -euo pipefail
export AWS_REGION=ap-northeast-2

kubectl delete ingress podinfo -n loadlab --ignore-not-found
kubectl delete namespace loadlab --ignore-not-found

# ALB가 실제로 사라졌는지 확인 (k8s-loadlab* 이름으로 생성됨)
echo "ALB 소멸 대기 중..."
for i in $(seq 1 18); do
  LEFT=$(aws elbv2 describe-load-balancers --region $AWS_REGION \
    --query "LoadBalancers[?contains(LoadBalancerName, 'loadlab')].LoadBalancerName" --output text)
  [ -z "$LEFT" ] && break
  sleep 10
done

if [ -n "${LEFT:-}" ]; then
  echo "⚠️  아직 남은 LB: $LEFT — 콘솔/CLI로 수동 삭제 필요 (시간당 과금 중!)"
else
  echo "모듈 14 정리 완료 — LB 잔재 없음"
fi
