#!/usr/bin/env bash
# 모듈 05 정리 — 실험 저장소, 로컬 컨테이너
set -euo pipefail

docker rm -f pg-test 2>/dev/null || true

cd ~/ci-lab/testing 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/testing

echo "모듈 05 정리 완료 — 초급 트랙(01~05) 졸업"
echo "테스트 정책 문서는 보존하세요. 23(파이프라인 관측성)에서 flaky 추이를 지표로 승격합니다."
