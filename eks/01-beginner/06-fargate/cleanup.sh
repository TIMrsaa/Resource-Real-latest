#!/usr/bin/env bash
# 모듈 06 정리 — Fargate 프로파일/워크로드
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}
CLUSTER=${CLUSTER:-k8s-study}
kubectl delete namespace serverless --ignore-not-found
kubectl delete namespace aws-observability --ignore-not-found
kubectl delete pod normal-probe --ignore-not-found
eksctl delete fargateprofile --cluster "$CLUSTER" --region "$AWS_REGION" --name fp-serverless 2>/dev/null || true
echo "모듈 06 정리 완료 — eks 초급 트랙(01~06) 수료!"
