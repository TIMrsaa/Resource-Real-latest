#!/usr/bin/env bash
# 모듈 23 정리 — vcluster 2개, 모형 리전/라우터, fleet 파일
set -euo pipefail

vcluster delete cluster-a -n vc-a 2>/dev/null || true
vcluster delete cluster-b -n vc-b 2>/dev/null || true
kubectl delete namespace vc-a vc-b global region-a region-b --ignore-not-found

rm -rf fleet/

echo "모듈 23 정리 완료"
