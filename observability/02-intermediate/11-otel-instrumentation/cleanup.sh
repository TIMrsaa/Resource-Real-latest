#!/usr/bin/env bash
# 모듈 11 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name otel 2>/dev/null || true

echo "모듈 11 정리 완료"
echo "★ 기억할 것: 수집기의 사상은 하나입니다(가까이서 받고, 가공하고, 중앙에서 정책) — 그리고 계측은 공짜가 아닙니다(오버헤드 예산)"
