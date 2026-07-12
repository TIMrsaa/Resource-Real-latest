#!/usr/bin/env bash
# 모듈 32 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name kyverno 2>/dev/null || true

echo "모듈 32 정리 완료"
echo "★ 기억할 것: 정책 엔진 도입은 소유권 지도에 새 주인을 추가하는 것 — 경계를 그려라"
