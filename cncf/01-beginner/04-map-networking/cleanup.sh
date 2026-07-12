#!/usr/bin/env bash
# 모듈 04 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name cilium 2>/dev/null || true

echo "모듈 04 정리 완료"
