#!/usr/bin/env bash
# 모듈 39 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name rook 2>/dev/null || true

echo "모듈 39 정리 완료"
echo "★ 기억할 것: Rook은 Ceph 운영 지식을 코드화하지만 없애지 않습니다 (심각한 장애엔 Ceph를 알아야)"
