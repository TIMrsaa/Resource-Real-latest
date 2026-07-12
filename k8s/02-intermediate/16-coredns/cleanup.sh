#!/usr/bin/env bash
# 모듈 16 정리
set -euo pipefail
kubectl delete pod dnsutil lowdots --ignore-not-found
kubectl delete deployment echo --ignore-not-found
kubectl delete svc echo echo-headless --ignore-not-found
# Corefile 백업이 남아 있으면 복구 안내
if [ -f /tmp/coredns-backup.yaml ]; then
  echo "주의: /tmp/coredns-backup.yaml 존재 — Corefile 원복이 안 됐을 수 있음:"
  echo "  kubectl apply -f /tmp/coredns-backup.yaml"
fi
echo "모듈 16 정리 완료"
