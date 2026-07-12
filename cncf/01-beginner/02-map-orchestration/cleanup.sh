#!/usr/bin/env bash
# 모듈 02 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name sched 2>/dev/null || true

echo "모듈 02 정리 완료"
echo "ℹ️  ~/cncf-lab/landscape 는 지도 모듈 공용 — 유지"
