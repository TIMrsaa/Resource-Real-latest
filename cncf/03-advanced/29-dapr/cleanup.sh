#!/usr/bin/env bash
# 모듈 29 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name dapr 2>/dev/null || true

echo "모듈 29 정리 완료"
echo "★ 기억할 것: 추상은 공짜가 아니라 새로운 신뢰 지점을 만든다"
