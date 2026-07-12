#!/usr/bin/env bash
# 모듈 22 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name metaobs 2>/dev/null || true
rm -f /tmp/fb-meta.yaml 2>/dev/null || true

echo "모듈 22 정리 완료"
echo "★ 기억할 것: 비용 공학은 삭감이 아니라 정렬입니다 — 모든 신호는 답할 질문이 있고, 모든 질문은 답할 신호가 있다"
