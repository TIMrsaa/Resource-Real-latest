#!/usr/bin/env bash
# 모듈 17 정리
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}
helm uninstall webapp-dev -n helm-dev 2>/dev/null || true
helm uninstall webapp-prod -n helm-prod 2>/dev/null || true
kubectl delete namespace helm-dev helm-prod --ignore-not-found
# 차트용 ECR (만들었다면)
aws ecr delete-repository --repository-name charts/webapp --region "$AWS_REGION" --force 2>/dev/null || true
echo "로컬 ~/helm-lab 디렉터리는 학습 산출물이므로 직접 판단해 삭제: rm -rf ~/helm-lab"
echo "모듈 17 정리 완료"
