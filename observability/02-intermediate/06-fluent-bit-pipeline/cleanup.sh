#!/usr/bin/env bash
# 모듈 06 정리 — kind 클러스터 + 임시 values
set -euo pipefail

kind delete cluster --name fluentbit 2>/dev/null || true
rm -f /tmp/fb-values.yaml 2>/dev/null || true

echo "모듈 06 정리 완료"
echo "★ 기억할 것: 유실 0이 아니라 '보이는 유실, 버티는 버퍼(fs), 의도된 포기(Retry_Limit)'가 수집기 설계다"
