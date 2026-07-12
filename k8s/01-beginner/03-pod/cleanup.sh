#!/usr/bin/env bash
# 모듈 03 정리 (클러스터는 유지)
set -euo pipefail
kubectl delete pod duo startup-order stubborn crasher --ignore-not-found
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
echo "모듈 03 리소스 정리 완료"
