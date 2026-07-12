#!/usr/bin/env bash
# 모듈 20 정리
set -euo pipefail
kubectl delete cronjob ticker failer --ignore-not-found
kubectl delete job pi flaky crowd-work sharded ticker-manual --ignore-not-found
kubectl delete jobs -l job-name --field-selector status.successful=1 --ignore-not-found 2>/dev/null || true
echo "모듈 20 정리 완료 — 중급(11~20) 전체 수료!"
