#!/usr/bin/env bash
# 모듈 24 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name istio 2>/dev/null || true

echo "모듈 24 정리 완료"
echo "★ 기억할 것: 메시는 기능이 아니라 비용 구조 — 무엇에 그 비용을 쓸지 정해야 한다"
