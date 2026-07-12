#!/usr/bin/env bash
# 모듈 29 정리
set -euo pipefail
kubectl delete pod resizable gated self-aware last-words shared-pid --ignore-not-found
kubectl delete job smart-retry --ignore-not-found
kubectl delete deployment topo --ignore-not-found
kubectl delete svc topo --ignore-not-found
echo "모듈 29 정리 완료"
