#!/usr/bin/env bash
# 모듈 06 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name observ 2>/dev/null || true

echo "모듈 06 정리 완료"
