#!/usr/bin/env bash
# 모듈 07 정리
set -euo pipefail
kubectl delete deployment config-demo --ignore-not-found
kubectl delete configmap app-config --ignore-not-found
kubectl delete secret db-cred regcred --ignore-not-found
kubectl delete pod missing-ref --ignore-not-found
echo "모듈 07 정리 완료"
