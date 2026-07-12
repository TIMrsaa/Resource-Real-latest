#!/usr/bin/env bash
# 모듈 13 정리
set -euo pipefail
kubectl delete hpa php-apache --ignore-not-found
kubectl delete vpa php-apache-vpa --ignore-not-found 2>/dev/null || true
kubectl delete deployment php-apache --ignore-not-found
kubectl delete svc php-apache --ignore-not-found
kubectl delete pod load-gen --ignore-not-found

# VPA 컴포넌트 제거 (설치했다면)
if [ -d /tmp/autoscaler/vertical-pod-autoscaler ]; then
  (cd /tmp/autoscaler/vertical-pod-autoscaler && ./hack/vpa-down.sh) || true
  rm -rf /tmp/autoscaler
fi
echo "모듈 13 정리 완료"
