#!/usr/bin/env bash
# 모듈 01 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name obs-tour 2>/dev/null || true

echo "모듈 01 정리 완료"
echo "★ 기억할 것: 관측 가능성은 도구가 아니라 '새 질문에 답할 수 있는 능력'입니다 — 신호는 이미 태어나 있고, 파이프라인은 나르는 일"
