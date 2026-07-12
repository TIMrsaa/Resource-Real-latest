#!/usr/bin/env bash
# 모듈 01 정리: 로컬 컨테이너/이미지 + ECR 리포지토리
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}

echo "[1/3] 로컬 컨테이너 제거"
docker rm -f sleeper limited web oom-test 2>/dev/null || true

echo "[2/3] 로컬 이미지/임시파일 제거"
docker rmi -f hello-k8s:v1 hello-k8s:v2 2>/dev/null || true
rm -rf ~/lab-image/img ~/lab-image/img.tar 2>/dev/null || true

echo "[3/3] ECR 리포지토리 삭제 (이미지 포함)"
aws ecr delete-repository --repository-name hello-k8s \
  --region "$AWS_REGION" --force 2>/dev/null || echo "  (이미 없음)"

echo "완료. EC2를 사용했다면 인스턴스 종료를 잊지 마세요:"
echo "  aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --region $AWS_REGION"
