#!/usr/bin/env bash
# 모듈 27 정리 — kind 클러스터, 클론
set -euo pipefail

kind delete cluster --name argo-dev 2>/dev/null || true
pkill -f "argocd|goreman" 2>/dev/null || true

rm -rf ~/contrib/argo-cd ~/contrib/gitops-engine ~/contrib/argo-rollouts

echo "모듈 27 정리 완료"
echo "ℹ️  실제 기여를 이어간다면 클론은 지우지 말고 fork를 origin으로 재설정해 사용"
