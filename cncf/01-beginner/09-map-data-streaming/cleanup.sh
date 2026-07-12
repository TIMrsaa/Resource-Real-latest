#!/usr/bin/env bash
# 모듈 09 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name data 2>/dev/null || true

echo "모듈 09 정리 완료"
echo "ℹ️  etcd 실습은 kind의 static Pod 대상 — 클러스터 삭제로 함께 제거됨"
