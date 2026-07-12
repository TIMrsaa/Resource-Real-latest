#!/usr/bin/env bash
# 모듈 05 정리 — kind 클러스터 + audit 임시 파일
set -euo pipefail

kind delete cluster --name signals 2>/dev/null || true
rm -rf /tmp/audit 2>/dev/null || true

echo "모듈 05 정리 완료 (beginner 트랙 수료)"
echo "★ 기억할 것: 휘발된 신호는 없는 신호입니다 — 과거·패턴·간헐 문제는 보존된 신호만이 답합니다 (파이프라인의 존재 이유)"
