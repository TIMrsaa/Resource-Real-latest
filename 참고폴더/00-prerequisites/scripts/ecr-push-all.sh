#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
SERVICES=(order-service payment-service user-service notification-service frontend)

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

# 이 스크립트의 위치 기준으로 scenarios 디렉토리 이동
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/../../scenarios"

for svc in "${SERVICES[@]}"; do
  echo "▶ Building ${svc}..."
  docker build -t "${REGISTRY}/eks-study/${svc}:latest" -f "${svc}/Dockerfile" .
  echo "▶ Pushing ${svc}..."
  docker push "${REGISTRY}/eks-study/${svc}:latest"
done

echo ""
echo "✅ 모든 이미지 푸시 완료"
echo ""
echo "푸시된 이미지:"
for svc in "${SERVICES[@]}"; do
  echo "  - ${REGISTRY}/eks-study/${svc}:latest"
done
