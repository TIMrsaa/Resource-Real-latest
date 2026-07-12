#!/usr/bin/env bash
# 모듈 21 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name slo 2>/dev/null || true

echo "모듈 21 정리 완료"
echo "★ 기억할 것: 100%는 목표가 아닙니다 — 버짓은 혁신의 예산이고, 알림은 '약속을 지킬 수 없는 속도'로 울린다"
