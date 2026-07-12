#!/usr/bin/env bash
# 모듈 12 정리 — 수집(과금) 중지가 최우선: 애드온 → 알람/SNS → 로그 그룹 → IAM
set -euo pipefail
export AWS_REGION=ap-northeast-2
CLUSTER=k8s-study
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1) 워크로드
kubectl delete namespace obs --ignore-not-found

# 2) 애드온 제거 = 수집 중지 (agent/fluent-bit DS까지 함께 정리됨)
aws eks delete-addon --cluster-name $CLUSTER --region $AWS_REGION \
  --addon-name amazon-cloudwatch-observability 2>/dev/null || true

# 3) 알람/SNS
aws cloudwatch delete-alarms --region $AWS_REGION \
  --alarm-names obs-lab-node-cpu obs-lab-ingest-bytes 2>/dev/null || true
aws sns delete-topic --region $AWS_REGION \
  --topic-arn arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:obs-lab-alerts 2>/dev/null || true

# 4) 로그 그룹 (남기면 저장 과금 지속)
for g in application dataplane host performance; do
  aws logs delete-log-group --region $AWS_REGION \
    --log-group-name /aws/containerinsights/$CLUSTER/$g 2>/dev/null || true
done

# 5) IAM (association은 애드온 삭제와 함께 정리 — 역할/정책 분리 삭제)
aws iam detach-role-policy --role-name CWObservabilityLab \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null || true
aws iam delete-role --role-name CWObservabilityLab 2>/dev/null || true
rm -f cw-trust.json

echo "모듈 12 정리 완료 — describe-log-groups로 /aws/containerinsights 잔재 없는지 확인"
