#!/usr/bin/env bash
# 모듈 27 정리 — kind 클러스터, 로컬 파일
set -euo pipefail

kind delete cluster --name crio-concept 2>/dev/null || true
rm -rf ~/cncf-lab/crio

echo "모듈 27 정리 완료 — 런타임 층(03·26·27) 종료"
echo "★ 기억할 것: 우리가 무엇을 쓰는지 아는 것이 먼저입니다 (CRI 위에서는 같아도 아래는 다른 세계)"
