#!/usr/bin/env bash
# 모듈 09 정리
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}
CLUSTER=${CLUSTER:-k8s-study}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

kubectl delete namespace iam-lab --ignore-not-found
# Pod Identity association
AID=$(aws eks list-pod-identity-associations --cluster-name "$CLUSTER" --region "$AWS_REGION" \
  --namespace iam-lab --query 'associations[0].associationId' --output text 2>/dev/null) || true
[ -n "${AID:-}" ] && [ "$AID" != "None" ] && aws eks delete-pod-identity-association \
  --cluster-name "$CLUSTER" --region "$AWS_REGION" --association-id "$AID"
# 역할들
for R in irsa-s3-reader pi-s3-reader; do
  aws iam detach-role-policy --role-name $R --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess 2>/dev/null || true
  aws iam delete-role --role-name $R 2>/dev/null || true
done
rm -f trust-irsa.json trust-pi.json
echo "모듈 09 정리 완료 (OIDC 공급자/PI 에이전트는 유지 — 이후 모듈 사용)"
