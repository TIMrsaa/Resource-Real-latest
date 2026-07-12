#!/usr/bin/env bash
# 모듈 09 정리 — kind 클러스터 + 임시 JSON
set -euo pipefail

kind delete cluster --name grafana 2>/dev/null || true
rm -f /tmp/red-dashboard.json /tmp/overview-dashboard.json 2>/dev/null || true

echo "모듈 09 정리 완료"
echo "★ 기억할 것: 대시보드의 성공 지표는 장수가 아니라 장애 때 사용 시간 — 패널마다 '어떤 질문의 답인가'"
