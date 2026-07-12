#!/usr/bin/env bash
# 모듈 03 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name runtime 2>/dev/null || true

echo "모듈 03 정리 완료"
