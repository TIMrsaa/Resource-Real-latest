#!/usr/bin/env bash
# 모듈 05 정리 — 추가한 노드그룹 삭제 (비용 차단)
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}
CLUSTER=${CLUSTER:-k8s-study}
kubectl delete job spot-job --ignore-not-found 2>/dev/null || true
kubectl delete pod normal --ignore-not-found 2>/dev/null || true
eksctl delete nodegroup --cluster "$CLUSTER" --region "$AWS_REGION" --name br-test --drain=false 2>/dev/null || true
eksctl delete nodegroup --cluster "$CLUSTER" --region "$AWS_REGION" --name spot-batch --drain=false 2>/dev/null || true
rm -f batch-pool.yaml br-pool.yaml
echo "노드그룹 삭제는 수 분 소요 — 확인: eksctl get nodegroup --cluster $CLUSTER --region $AWS_REGION"
echo "모듈 05 정리 완료"
