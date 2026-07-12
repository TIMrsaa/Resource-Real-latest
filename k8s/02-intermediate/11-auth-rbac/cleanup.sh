#!/usr/bin/env bash
# 모듈 11 정리
set -euo pipefail
kubectl delete namespace rbac-lab --ignore-not-found
kubectl delete clusterrolebinding viewers-binding --ignore-not-found
echo "모듈 11 정리 완료"
