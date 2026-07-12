#!/usr/bin/env bash
# 모듈 02 정리 — 연기용 역할/entry 제거
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}
CLUSTER=${CLUSTER:-k8s-study}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for R in eks-newbie eks-deploy-bot; do
  aws eks delete-access-entry --cluster-name "$CLUSTER" --region "$AWS_REGION" \
    --principal-arn arn:aws:iam::$ACCOUNT_ID:role/$R 2>/dev/null || true
  aws iam delete-role --role-name $R 2>/dev/null || true
done
kubectl delete deployment web -n shop --ignore-not-found 2>/dev/null || true
kubectl delete namespace shop --ignore-not-found
rm -f ~/eks-lab/trust.json
echo "모듈 02 정리 완료 (cluster.yaml은 보존 — 파트 내내 사용)"
