#!/usr/bin/env bash
# 모듈 18 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name keda 2>/dev/null || true

echo "모듈 18 정리 완료"
echo "★ 기억할 것: 오토스케일러가 지키는 것은 replicas이지 당신의 메시지가 아니다"
