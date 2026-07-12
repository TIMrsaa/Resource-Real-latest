#!/usr/bin/env bash
# 모듈 13 정리 — kind 클러스터, port-forward
set -euo pipefail

pkill -f "port-forward.*16686" 2>/dev/null || true
kind delete cluster --name jaeger 2>/dev/null || true

echo "모듈 13 정리 완료"
echo "★ 기억할 것: 트레이스의 가치는 저장량이 아니라 알람→원인까지의 거리"
