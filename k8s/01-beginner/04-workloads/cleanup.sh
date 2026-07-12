#!/usr/bin/env bash
# 모듈 04 정리 (클러스터는 유지)
set -euo pipefail
kubectl delete deployment web --ignore-not-found
kubectl delete daemonset node-agent --ignore-not-found
kubectl delete pods -l pod-template-hash --field-selector status.phase!=Running --ignore-not-found 2>/dev/null || true
echo "모듈 04 리소스 정리 완료"
