#!/usr/bin/env bash
# 모듈 21 정리 — kind 클러스터, 실습 저장소, 로컬 파일
set -euo pipefail

kind delete cluster --name supply 2>/dev/null || true

cd ~/ci-lab/supply 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/supply

echo "모듈 21 정리 완료"
echo "ℹ️  ghcr.io 이미지·서명은 저장소 삭제로 함께 제거"
echo "ℹ️  Rekor의 공개 로그 항목은 삭제 불가(append-only) — 실습 기록이 남지만 무해"
