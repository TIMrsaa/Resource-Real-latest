#!/usr/bin/env bash
# 모듈 09 정리 — 파이프라인(월정액), CodeBuild, S3, IAM, Connection, 저장소
set -euo pipefail
export AWS_REGION=${AWS_REGION:-ap-northeast-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws codepipeline delete-pipeline --name cicd-lab-pipeline --region $AWS_REGION 2>/dev/null || true
aws codebuild delete-project --name cicd-lab-build --region $AWS_REGION 2>/dev/null || true

aws sns delete-topic --topic-arn arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:cicd-lab-approvals 2>/dev/null || true

CONN=$(aws codeconnections list-connections --region $AWS_REGION \
  --query "Connections[?ConnectionName=='cicd-lab-conn'].ConnectionArn" --output text 2>/dev/null || echo "")
[ -n "$CONN" ] && aws codeconnections delete-connection --connection-arn $CONN --region $AWS_REGION 2>/dev/null || true

aws s3 rb s3://cicd-lab-artifacts-$ACCOUNT_ID --force 2>/dev/null || true

for R in cicd-lab-pipeline cicd-lab-build; do
  for P in $(aws iam list-role-policies --role-name $R --query PolicyNames --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name $R --policy-name $P 2>/dev/null || true
  done
  aws iam delete-role --role-name $R 2>/dev/null || true
done

cd ~/ci-lab/codepipe 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/codepipe

echo "모듈 09 정리 완료"
