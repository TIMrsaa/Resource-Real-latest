#!/usr/bin/env bash
# 모듈 03 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name metrics 2>/dev/null || true

echo "모듈 03 정리 완료"
echo "★ 기억할 것: 타입은 숫자를 읽는 계약(counter는 rate로, 분포는 분위수로)이고, 라벨은 곱셈(unbounded 금지)이다"
