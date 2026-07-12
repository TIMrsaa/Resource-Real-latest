#!/usr/bin/env bash
# 모듈 38 정리
set -euo pipefail
kubectl delete namespace dr-lab --ignore-not-found
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
echo "모듈 38 정리 완료"
