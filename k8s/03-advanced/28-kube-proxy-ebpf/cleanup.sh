#!/usr/bin/env bash
# 모듈 28 정리
set -euo pipefail
kubectl delete deployment chain --ignore-not-found
kubectl delete svc chain --ignore-not-found
kubectl delete pod cc --ignore-not-found
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
echo "모듈 28 정리 완료"
