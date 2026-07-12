#!/usr/bin/env bash
# 모듈 22 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name cilium 2>/dev/null || true
rm -f /tmp/kind-cilium.yaml

echo "모듈 22 정리 완료"
echo "★ 기억할 것: 도구의 성능은 그것을 어느 경로로 쓰느냐가 정합니다 (eBPF 빠른 길 vs Envoy 느린 길)"
