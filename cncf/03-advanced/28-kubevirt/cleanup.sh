#!/usr/bin/env bash
# 모듈 28 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name kubevirt 2>/dev/null || true

echo "모듈 28 정리 완료"
echo "★ 기억할 것: 컨테이너 네이티브가 아닌 것을 K8s에 올리면, 그 운영 지식도 함께 필요하다"
