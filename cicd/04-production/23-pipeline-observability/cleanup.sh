#!/usr/bin/env bash
# 모듈 23 정리 — 실습 저장소
set -euo pipefail

cd ~/ci-lab/observ 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/observ

echo "모듈 23 정리 완료"
echo "ℹ️  스케줄 워크플로(weekly-metrics)는 저장소 삭제로 함께 제거됨"
