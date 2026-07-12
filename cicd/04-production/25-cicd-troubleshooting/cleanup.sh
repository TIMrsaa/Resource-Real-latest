#!/usr/bin/env bash
# 모듈 25 정리 — 실습 저장소, 로컬 이미지
set -euo pipefail

docker rmi -f fake-app:latest 2>/dev/null || true

cd ~/ci-lab/trouble 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/trouble

echo "모듈 25 정리 완료"
echo "ℹ️  GHA 캐시(deps-cache-*)는 저장소 삭제로 함께 제거됨"
