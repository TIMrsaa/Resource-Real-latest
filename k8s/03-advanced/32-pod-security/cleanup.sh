#!/usr/bin/env bash
# 모듈 32 정리
set -euo pipefail
kubectl delete pod naked nonroot-fail nonroot-ok no-caps ro-fs no-esc secure-app --ignore-not-found
kubectl delete namespace secure-zone --ignore-not-found
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
echo "모듈 32 정리 완료 — 고급 트랙(21~32) 전체 수료!"
