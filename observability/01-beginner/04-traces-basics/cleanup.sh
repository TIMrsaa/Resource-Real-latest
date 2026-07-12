#!/usr/bin/env bash
# 모듈 04 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name traces 2>/dev/null || true

echo "모듈 04 정리 완료"
echo "★ 기억할 것: 전파의 실체는 ID 릴레이(traceparent 옮겨 붙이기)이고, 트레이스의 가치는 가장 약한 고리가 정한다"
