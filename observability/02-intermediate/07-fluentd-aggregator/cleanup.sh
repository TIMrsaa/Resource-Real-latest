#!/usr/bin/env bash
# 모듈 07 정리 — kind 클러스터 + 임시 values
set -euo pipefail

kind delete cluster --name twotier 2>/dev/null || true
rm -f /tmp/fb-forward.yaml 2>/dev/null || true

echo "모듈 07 정리 완료"
echo "★ 기억할 것: 집계층은 정책의 단일점이자 장애의 증폭점 — 버퍼 격리·계단식 알림·HA가 그 규율이다"
