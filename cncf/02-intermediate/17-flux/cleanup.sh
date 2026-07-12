#!/usr/bin/env bash
# 모듈 17 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name flux 2>/dev/null || true
rm -f /tmp/source.yaml

echo "모듈 17 정리 완료"
echo "★ 기억할 것: GitOps의 '자동'은 배포의 자동이지 판단의 자동이 아니다"
