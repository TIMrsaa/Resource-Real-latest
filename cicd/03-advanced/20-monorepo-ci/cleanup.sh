#!/usr/bin/env bash
# 모듈 20 정리 — 모노레포 실습 저장소
set -euo pipefail

cd ~/ci-lab/mono 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/mono

echo "모듈 20 정리 완료"
echo "ℹ️  브랜치 보호를 실험했다면 저장소 삭제로 함께 제거됨"
