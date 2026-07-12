#!/usr/bin/env bash
# 모듈 24 정리 — 실습 저장소 (environment 포함)
set -euo pipefail

cd ~/ci-lab/enterprise 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/enterprise

echo "모듈 24 정리 완료"
echo "ℹ️  production environment·승인 대기 런은 저장소 삭제로 함께 제거됨"
