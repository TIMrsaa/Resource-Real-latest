#!/usr/bin/env bash
# 모듈 36 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name vitess 2>/dev/null || true

echo "모듈 36 정리 완료"
echo "★ 기억할 것: 가장 스테이트풀한 도구일수록 '정말 필요한가'와 '정말 자체 운영해야 하나'를 먼저"
