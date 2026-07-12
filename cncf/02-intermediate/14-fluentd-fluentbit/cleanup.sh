#!/usr/bin/env bash
# 모듈 14 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name logs 2>/dev/null || true
rm -f /tmp/fb-values.yaml /tmp/fb-tiny.yaml /tmp/fb-json.yaml

echo "모듈 14 정리 완료 — 관측 심층 트랙(11~14) 종료"
echo "★ 결론: 도구를 다 갖춰도 trace_id 하나가 없으면 조사 동선이 끊긴다"
