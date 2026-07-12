#!/usr/bin/env bash
# 모듈 18 정리 — Flow Logs 중지(비용)부터, 로그 그룹·IAM·실험 ns까지
set -euo pipefail
export AWS_REGION=ap-northeast-2
CLUSTER=k8s-study
VPC=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)

# 1) Flow Logs 중지
FLID=$(aws ec2 describe-flow-logs --region $AWS_REGION \
  --filter "Name=resource-id,Values=$VPC" "Name=log-group-name,Values=/vpc/flowlogs-lab" \
  --query 'FlowLogs[].FlowLogId' --output text)
[ -n "$FLID" ] && aws ec2 delete-flow-logs --flow-log-ids $FLID --region $AWS_REGION

# 2) 로그 그룹 (저장 과금 중지)
aws logs delete-log-group --log-group-name /vpc/flowlogs-lab --region $AWS_REGION 2>/dev/null || true

# 3) IAM
aws iam delete-role-policy --role-name FlowLogsLab --policy-name write-logs 2>/dev/null || true
aws iam delete-role --role-name FlowLogsLab 2>/dev/null || true

# 4) 실험 리소스
kubectl delete namespace netlab --ignore-not-found
# kubectl debug의 잔재 Pod 청소
for p in $(kubectl get pods -A --no-headers 2>/dev/null | awk '/node-debugger/{print $2" -n "$1}'); do
  kubectl delete pod $p --ignore-not-found 2>/dev/null || true
done

rm -f fl-trust.json

echo "모듈 18 정리 완료 — describe-flow-logs로 잔재 없는지 확인"
