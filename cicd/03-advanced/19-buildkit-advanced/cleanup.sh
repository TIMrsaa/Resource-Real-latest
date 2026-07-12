#!/usr/bin/env bash
# 모듈 19 정리 — buildx 빌더, 로컬 이미지, GHA 저장소
set -euo pipefail

docker buildx rm lab 2>/dev/null || true
docker rmi -f lab:dag lab:cache lab:emu lab:cross lab-cnb 2>/dev/null || true
docker buildx prune -af >/dev/null 2>&1 || true

cd ~/ci-lab/buildkit 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/buildkit

echo "모듈 19 정리 완료"
echo "ℹ️  ttl.sh 이미지는 1시간 후 자동 삭제 / ghcr.io 캐시 이미지는 저장소 삭제로 함께 제거"
echo "ℹ️  binfmt(QEMU) 등록은 재부팅 시 초기화 — 유지해도 무해"
