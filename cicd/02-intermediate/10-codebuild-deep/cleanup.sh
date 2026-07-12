#!/usr/bin/env bash
# 모듈 10 정리 — CodeBuild 프로젝트, ECR, IAM, access entry, S3, 저장소
set -euo pipefail
export AWS_REGION=${AWS_REGION:-ap-northeast-2}
CLUSTER=k8s-study
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws codebuild delete-project --name cb-lab --region $AWS_REGION 2>/dev/null || true
aws ecr delete-repository --repository-name cb-lab-app --region $AWS_REGION --force 2>/dev/null || true

kubectl delete rolebinding cb-deploy -n default --ignore-not-found 2>/dev/null || true
kubectl delete role cb-deploy -n default --ignore-not-found 2>/dev/null || true
eksctl delete accessentry --cluster $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/cb-lab-role 2>/dev/null || true

for P in $(aws iam list-role-policies --role-name cb-lab-role --query PolicyNames --output text 2>/dev/null); do
  aws iam delete-role-policy --role-name cb-lab-role --policy-name $P 2>/dev/null || true
done
aws iam delete-role --role-name cb-lab-role 2>/dev/null || true

aws s3 rb s3://cb-lab-cache-$ACCOUNT_ID --force 2>/dev/null || true

cd ~/ci-lab/cbuild 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/cbuild

echo "모듈 10 정리 완료"
