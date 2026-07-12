#!/usr/bin/env bash
# 모듈 22 정리 — OpenCost/Prometheus/실험 ns
set -euo pipefail

helm uninstall opencost -n opencost 2>/dev/null || true
helm uninstall prometheus -n monitoring 2>/dev/null || true
kubectl delete namespace opencost monitoring team-a rogue --ignore-not-found

rm -f gap-report.sh

echo "모듈 22 정리 완료"
