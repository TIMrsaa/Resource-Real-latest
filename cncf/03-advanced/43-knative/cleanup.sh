#!/usr/bin/env bash
# 모듈 43 정리 — kind 클러스터 (knative quickstart가 만든 것)
set -euo pipefail

kind delete cluster --name knative 2>/dev/null || true

echo "모듈 43 정리 완료"
echo "★ 기억할 것: scale-to-zero는 비용을 0으로 만들지만 콜드 스타트라는 물리적 대가가 있습니다 (자동화가 물리를 숨기지만 없애지 않음)"
