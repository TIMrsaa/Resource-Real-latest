#!/usr/bin/env bash
# 모듈 17 정리 — Rollout/Analysis, Prometheus, Argo Rollouts
set -euo pipefail

kubectl delete namespace pdlab --ignore-not-found
helm uninstall prometheus -n monitoring 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found

kubectl delete -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml 2>/dev/null || true
kubectl delete namespace argo-rollouts --ignore-not-found

echo "모듈 17 정리 완료 — 안전 자동화(11+14+15+eks13) 완성"
