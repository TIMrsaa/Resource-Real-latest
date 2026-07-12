#!/usr/bin/env bash
# 모듈 02 정리 — 실험 저장소(로컬 + GitHub)
set -euo pipefail

cd ~/ci-lab/protect 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/{flow,ghflow,trunk,protect}

echo "모듈 02 정리 완료 — 팀 규칙 문서는 보존하세요 (03에서 'ci' 필수 검사를 구현합니다)"
