#!/usr/bin/env bash
# 모듈 14 정리 — Application/ApplicationSet, 워크로드, ArgoCD, config repo
set -euo pipefail

# Application 먼저 삭제 (prune으로 워크로드도 정리됨)
kubectl -n argocd delete applicationset fleet --ignore-not-found
kubectl -n argocd delete application demo --ignore-not-found
sleep 10
kubectl delete namespace gitops-demo gitops-fleet --ignore-not-found

# ArgoCD 제거
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null || true
kubectl delete namespace argocd --ignore-not-found

cd ~/ci-lab/gitops 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/gitops

echo "모듈 14 정리 완료"
