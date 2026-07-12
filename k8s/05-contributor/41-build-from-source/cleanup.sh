#!/usr/bin/env bash
# 모듈 41 정리 — 클러스터/이미지만 (소스 리포는 42~45에서 계속 사용!)
set -euo pipefail
kind delete cluster --name mykube 2>/dev/null || true
docker rmi kindest/node:my-build 2>/dev/null || true
# 소스의 실험 흔적 원복
git -C ~/go/src/k8s.io/kubernetes checkout -- . 2>/dev/null || true
echo "모듈 41 정리 완료 (~/go/src/k8s.io/kubernetes 는 유지)"
