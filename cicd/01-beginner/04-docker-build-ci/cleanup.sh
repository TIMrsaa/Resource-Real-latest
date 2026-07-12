#!/usr/bin/env bash
# 모듈 04 정리 — ECR 리포지토리(과금), GitHub 저장소와 시크릿, 로컬 이미지
set -euo pipefail
export AWS_REGION=${AWS_REGION:-ap-northeast-2}

# ECR (이미지 저장 과금)
aws ecr delete-repository --repository-name cicd-lab-app --region $AWS_REGION --force 2>/dev/null || true

# GitHub 저장소 (시크릿에 든 AWS 키도 함께 사라집니다)
cd ~/ci-lab/buildci 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/{build,buildci}

docker rmi -f demo:bad demo:good demo:cm demo:leak demo:secret demo:single demo:multi 2>/dev/null || true
docker builder prune -f >/dev/null 2>&1 || true

echo "모듈 04 정리 완료"
echo "⚠️  실제 프로젝트에서 CI에 장기 AWS 키를 넣었다면 — 07(OIDC) 완료 후 반드시 삭제·회전하라"
