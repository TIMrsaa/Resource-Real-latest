#!/usr/bin/env bash
# 모듈 34 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name harbor 2>/dev/null || true

echo "모듈 34 정리 완료"
echo "★ 기억할 것: 레지스트리가 공급망의 관문이라면, 그 관문 자체의 가용성·백업이 공급망의 전제"
