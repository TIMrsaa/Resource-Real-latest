#!/usr/bin/env bash
# 모듈 46 정리 — kind 클러스터 (전체 플랫폼)
set -euo pipefail

pkill -f "port-forward" 2>/dev/null || true
kind delete cluster --name platform 2>/dev/null || true

echo "모듈 46 정리 완료"
echo "★ 기억할 것: 플랫폼은 층·의존·순서입니다 — 개별 프로젝트를 아는 것과 조립하는 것은 다른 능력(관측 먼저, 점진적으로)"
