#!/usr/bin/env bash
# 모듈 18 정리 — 액션 저장소 (로컬 개발)
set -euo pipefail

cd ~/ci-lab/action 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/action

echo "모듈 18 정리 완료"
echo "ℹ️  마켓플레이스에 배포했다면 릴리스 페이지에서 unpublish"
