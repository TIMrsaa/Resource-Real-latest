#!/usr/bin/env bash
# 모듈 44 정리
set -euo pipefail
kind delete cluster --name e2e-lab 2>/dev/null || true
git -C ~/go/src/k8s.io/kubernetes checkout -- . 2>/dev/null || true
echo "모듈 44 정리 완료 (~/k8s-test-lab 과 소스 리포는 유지)"
