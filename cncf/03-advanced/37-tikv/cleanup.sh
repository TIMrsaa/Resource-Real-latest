#!/usr/bin/env bash
# 모듈 37 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name tikv 2>/dev/null || true

echo "모듈 37 정리 완료"
echo "★ 기억할 것: 자동화는 물리를 숨기지만 없애지 않습니다 (핫스팟·디스크·PD는 여전히)"
