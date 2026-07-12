#!/usr/bin/env bash
# 모듈 08 정리 — kind 클러스터, 로컬 차트/오버레이
set -euo pipefail

kind delete cluster --name delivery 2>/dev/null || true
rm -rf ~/cncf-lab/delivery

echo "모듈 08 정리 완료"
echo "ℹ️  ~/cncf-lab/landscape 는 지도 모듈 공용 — 유지"
