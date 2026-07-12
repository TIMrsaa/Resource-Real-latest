#!/usr/bin/env bash
# 모듈 02 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name logging 2>/dev/null || true

echo "모듈 02 정리 완료"
echo "★ 기억할 것: 노드 로그는 임시 버퍼(10Mi×5)입니다 — 보존은 파이프라인의 몫이고, 로그 품질(구조화)은 앱 코드에서 결정된다"
