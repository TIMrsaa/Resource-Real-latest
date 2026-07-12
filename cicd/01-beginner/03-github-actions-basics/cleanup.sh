#!/usr/bin/env bash
# 모듈 03 정리 — 실험 저장소 (Actions 사용량도 함께 정리됨)
set -euo pipefail

cd ~/ci-lab/gha 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/gha

echo "모듈 03 정리 완료 — ci.yml 스켈레톤은 04~06에서 확장합니다 (설계 노트 보존)"
