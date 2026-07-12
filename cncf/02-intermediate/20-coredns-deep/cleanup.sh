#!/usr/bin/env bash
# 모듈 20 정리 — kind 클러스터
set -euo pipefail

pkill -f "port-forward.*9153" 2>/dev/null || true
kind delete cluster --name dns 2>/dev/null || true
rm -f /tmp/Corefile.bak

echo "모듈 20 정리 완료"
echo "★ 기억할 것: CoreDNS를 관측하는 것과 DNS를 관측하는 것은 다르다"
