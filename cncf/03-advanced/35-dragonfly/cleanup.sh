#!/usr/bin/env bash
# 모듈 35 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name dragonfly 2>/dev/null || true

echo "모듈 35 정리 완료"
echo "★ 기억할 것: 최적화는 도입보다 검증이 중요합니다 (조용히 무력화될 수 있으므로)"
