#!/usr/bin/env bash
# 모듈 14 정리
set -euo pipefail
kubectl delete deployment probe-demo --ignore-not-found
kubectl delete svc probe-demo --ignore-not-found
kubectl delete pod loader slow-boot --ignore-not-found
echo "모듈 14 정리 완료"
