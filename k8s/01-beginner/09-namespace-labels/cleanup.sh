#!/usr/bin/env bash
# 모듈 09 정리
set -euo pipefail
kubectl config set-context --current --namespace=default
kubectl delete namespace dev staging --ignore-not-found
kubectl delete pods -l 'env in (dev,staging,prod)' --ignore-not-found
echo "모듈 09 정리 완료"
