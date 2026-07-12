#!/usr/bin/env bash
# 모듈 33 정리
set -euo pipefail
kubectl delete job kube-bench --ignore-not-found
echo "모듈 33 정리 완료"
