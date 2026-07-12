#!/usr/bin/env bash
# 모듈 16 정리 — kind 클러스터 2개
set -euo pipefail

kind delete cluster --name hub 2>/dev/null || true
kind delete cluster --name spoke 2>/dev/null || true

echo "모듈 16 정리 완료"
echo "★ 기억할 것: ApplicationSet은 앱을 만드는 앱이자, 앱을 지우는 앱이다"
