#!/usr/bin/env bash
# 모듈 27 정리
set -euo pipefail
kubectl delete pod net-target net-client --ignore-not-found
kubectl delete deployment ip-eater --ignore-not-found
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
echo "모듈 27 정리 완료"
