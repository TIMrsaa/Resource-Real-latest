#!/usr/bin/env bash
# 모듈 41 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name crossplane 2>/dev/null || true

echo "모듈 41 정리 완료"
echo "★ 기억할 것: Crossplane은 08의 조정 루프를 인프라로 확장합니다 — 힘(자동·지속)과 위험(실수의 즉시 전파)을 함께"
