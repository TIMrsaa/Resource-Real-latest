#!/usr/bin/env bash
# 모듈 25 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name linkerd 2>/dev/null || true

echo "모듈 25 정리 완료"
echo "★ 기억할 것: 메시 선택에 정답은 없습니다 — 요구와 운영 역량의 함수가 있을 뿐"
