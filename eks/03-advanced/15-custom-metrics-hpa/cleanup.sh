#!/usr/bin/env bash
# 모듈 15 정리 — ScaledObject/HPA → KEDA/Adapter/Prometheus → ns
set -euo pipefail

kubectl delete scaledobject podinfo -n scalelab --ignore-not-found
kubectl delete hpa podinfo-rps -n scalelab --ignore-not-found

helm uninstall keda -n keda 2>/dev/null || true
helm uninstall prometheus-adapter -n monitoring 2>/dev/null || true
helm uninstall prometheus -n monitoring 2>/dev/null || true

kubectl delete namespace scalelab keda monitoring --ignore-not-found
rm -f adapter-values.yaml

echo "모듈 15 정리 완료 — kubectl get apiservice | grep metrics로 잔재 APIService 확인"
