#!/usr/bin/env bash
# 모듈 10 정리 — kind 클러스터 (MY-MAP.md는 보존!)
set -euo pipefail

kind delete cluster --name platform 2>/dev/null || true

echo "모듈 10 정리 완료"
echo "★ ~/cncf-lab/MY-MAP.md 는 지도 트랙의 졸업 산출물 — 삭제하지 말 것"
echo "  (심층 트랙 11~44를 진행하며 계속 갱신합니다)"
echo "ℹ️  landscape.yml·all-projects.txt도 분기 재집계에 재사용 — 유지"
