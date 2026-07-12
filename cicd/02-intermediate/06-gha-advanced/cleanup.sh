#!/usr/bin/env bash
# 모듈 06 정리 — 공용/소비자 저장소 (환경·시크릿 함께 삭제됨)
set -euo pipefail

for d in shared consumer; do
  cd ~/ci-lab/$d 2>/dev/null && {
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
    [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
    cd ~
  }
done
rm -rf ~/ci-lab/{shared,consumer}
rm -f /tmp/action.bak

echo "모듈 06 정리 완료 — 배포 통제 문서는 보존 (07에서 environment에 OIDC 역할을 붙입니다)"
