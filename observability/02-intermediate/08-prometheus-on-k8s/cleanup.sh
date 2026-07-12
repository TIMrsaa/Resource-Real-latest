#!/usr/bin/env bash
# 모듈 08 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name prom 2>/dev/null || true

echo "모듈 08 정리 완료"
echo "★ 기억할 것: 수집 체계 = 등록(ServiceMonitor) + 수문(relabeling·limit) + 정의의 단일화(recording rule)"
