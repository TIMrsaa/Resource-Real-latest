#!/usr/bin/env bash
# 모듈 07 정리 — IAM 역할·정책, ECR, 실험 저장소
# ⚠️ OIDC 제공자는 계정 공용일 수 있으므로 기본적으로 남깁니다
set -euo pipefail
export AWS_REGION=${AWS_REGION:-ap-northeast-2}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for ROLE in gha-oidc-lab gha-staging-lab gha-production-lab; do
  for P in $(aws iam list-role-policies --role-name $ROLE --query 'PolicyNames' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name $ROLE --policy-name $P 2>/dev/null || true
  done
  aws iam delete-role --role-name $ROLE 2>/dev/null || true
done

aws ecr delete-repository --repository-name cicd-oidc-app --region $AWS_REGION --force 2>/dev/null || true

for d in oidc attacker; do
  cd ~/ci-lab/$d 2>/dev/null && {
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
    [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
    cd ~
  }
done
rm -rf ~/ci-lab/{oidc,attacker}

echo "모듈 07 정리 완료"
echo "ℹ️  OIDC 제공자(token.actions.githubusercontent.com)는 남겨뒀습니다 — 계정 공용이면 유지, 아니면:"
echo "   aws iam delete-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
