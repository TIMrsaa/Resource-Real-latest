#!/usr/bin/env bash
# 모듈 11 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name prom 2>/dev/null || true
rm -f /tmp/prom.yml /tmp/prom-fixed.yml

echo "모듈 11 정리 완료"
echo "★ 실무 팁: 프로덕션 Prometheus에 promtool tsdb analyze 를 분기마다 —"
echo "  카디널리티는 조용히 자란다"
