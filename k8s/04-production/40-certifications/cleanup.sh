#!/usr/bin/env bash
# 모듈 40 정리
set -euo pipefail
kubectl delete namespace exam exam2 --ignore-not-found
rm -f job.yaml pod.yaml
echo "모듈 40 정리 완료 — 실무 트랙(33~40) 수료. 다음: 05-contributor"
