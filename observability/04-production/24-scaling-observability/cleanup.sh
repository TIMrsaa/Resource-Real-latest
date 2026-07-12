#!/usr/bin/env bash
# 모듈 24 정리 — kind 클러스터 + 임시 values
set -euo pipefail

kind delete cluster --name thanos 2>/dev/null || true
rm -f /tmp/prom-east.yaml /tmp/prom-west.yaml 2>/dev/null || true

echo "모듈 24 정리 완료 (production 트랙 수료)"
echo "★ 기억할 것: 규모가 바꾸는 것은 토폴로지뿐 — 기본기(규율·규약·동선)가 이식성입니다. 그리고 중앙화의 완료 기준은 '중앙이 죽어도 각자 생존하는가'"
