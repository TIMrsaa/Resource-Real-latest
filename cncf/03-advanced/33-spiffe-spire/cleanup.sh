#!/usr/bin/env bash
# 모듈 33 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name spire 2>/dev/null || true

echo "모듈 33 정리 완료"
echo "★ 기억할 것: 신원을 통일하며 새 신뢰의 뿌리를 만듭니다 — 그 뿌리를 지키는 것이 신원을 지키는 것"
