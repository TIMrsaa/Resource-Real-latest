#!/usr/bin/env bash
# 모듈 13 정리 — 부하 실험 ns 일괄 제거 (Job/CM/Deployment/Service 포함)
set -euo pipefail

kubectl delete namespace loadlab --ignore-not-found
rm -f load.js delay.js

echo "모듈 13 정리 완료 — kubectl top nodes로 부하 잔재(높은 CPU) 가라앉았는지 확인"
