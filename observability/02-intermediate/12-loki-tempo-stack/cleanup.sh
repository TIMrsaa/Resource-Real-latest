#!/usr/bin/env bash
# 모듈 12 정리 — kind 클러스터 + 임시 values
set -euo pipefail

kind delete cluster --name correlate 2>/dev/null || true
rm -f /tmp/fb-loki.yaml 2>/dev/null || true

echo "모듈 12 정리 완료 (intermediate 트랙 수료)"
echo "★ 기억할 것: 파이프라인은 절반이고 나머지 절반은 연결(trace_id·라벨 일관성·exemplar)입니다 — 성숙도는 신호 간 이동 시간"
