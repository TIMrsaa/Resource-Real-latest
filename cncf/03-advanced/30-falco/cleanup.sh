#!/usr/bin/env bash
# 모듈 30 정리 — kind 클러스터
set -euo pipefail

pkill -f "port-forward.*2801" 2>/dev/null || true
kind delete cluster --name falco 2>/dev/null || true

echo "모듈 30 정리 완료"
echo "★ 기억할 것: 탐지의 가치는 도구가 아니라 그것을 운영하는 규율에 있다"
