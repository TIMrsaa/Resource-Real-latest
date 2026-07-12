#!/usr/bin/env bash
# 모듈 38 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name nats 2>/dev/null || true

echo "모듈 38 정리 완료"
echo "★ 기억할 것: 도구의 유연함은 그 유연함을 이해할 때만 강점입니다 (core vs JetStream)"
