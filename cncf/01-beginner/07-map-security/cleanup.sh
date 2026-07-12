#!/usr/bin/env bash
# 모듈 07 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name security 2>/dev/null || true

echo "모듈 07 정리 완료"
echo "ℹ️  Falco의 커널 드라이버(eBPF)는 클러스터 삭제로 함께 제거됨"
echo "ℹ️  ~/cncf-lab/landscape 는 지도 모듈 공용 — 유지"
