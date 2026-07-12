#!/usr/bin/env bash
# 모듈 20 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name profiling 2>/dev/null || true

echo "모듈 20 정리 완료 (advanced 트랙 수료)"
echo "★ 기억할 것: 간헐 문제의 답은 재현이 아니라 보존입니다 — 그리고 조사의 종결 조건은 '범인 스택 지목'"
