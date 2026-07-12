#!/usr/bin/env bash
# 모듈 26 정리 — 러너 등록 해제, 실습 저장소, 클론
set -euo pipefail

# 러너가 아직 등록돼 있으면 해제 (lab-01 Step 7을 건너뛴 경우)
if [ -d ~/contrib/runner/_layout ] && [ -f ~/contrib/runner/_layout/.runner ]; then
  REPO=$(gh repo view runner-lab --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  if [ -n "$REPO" ]; then
    TOKEN=$(gh api -X POST "repos/${REPO}/actions/runners/remove-token" -q .token 2>/dev/null || echo "")
    [ -n "$TOKEN" ] && (cd ~/contrib/runner/_layout && ./config.sh remove --token "$TOKEN") || true
  fi
fi

gh repo delete runner-lab --yes 2>/dev/null || true
rm -rf ~/contrib/runner ~/contrib/toolkit ~/contrib/repro-demo ~/contrib/runner-lab

echo "모듈 26 정리 완료"
echo "ℹ️  ~/contrib 는 27·28에서 재사용 — 디렉터리 자체는 유지"
