#!/usr/bin/env bash
# 모듈 12 정리 — kind 클러스터, port-forward
set -euo pipefail

pkill -f "port-forward.*16686" 2>/dev/null || true
kind delete cluster --name otel 2>/dev/null || true
rm -f /tmp/cfg.yaml

echo "모듈 12 정리 완료"
echo "★ 기억할 것: OTel의 성공 지표 = 백엔드 교체 시 앱을 안 건드렸는가"
