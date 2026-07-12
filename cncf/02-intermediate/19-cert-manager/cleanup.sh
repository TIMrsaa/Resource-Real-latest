#!/usr/bin/env bash
# 모듈 19 정리 — kind 클러스터
set -euo pipefail

pkill -f "port-forward.*9402" 2>/dev/null || true
kind delete cluster --name certs 2>/dev/null || true
rm -f /tmp/tls.crt /tmp/ca.crt

echo "모듈 19 정리 완료"
echo "★ 기억할 것: cert-manager는 인증서를 잊게 해주지만, CA를 잊게 해주지는 않는다"
