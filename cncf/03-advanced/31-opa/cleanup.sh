#!/usr/bin/env bash
# 모듈 31 정리 — kind 클러스터, 로컬 rego
set -euo pipefail

kind delete cluster --name opa 2>/dev/null || true
rm -rf ~/cncf-lab/opa

echo "모듈 31 정리 완료"
echo "★ 기억할 것: 도구의 강점은 그것을 쓸 수 있는 사람이 있을 때만 강점이다"
