#!/usr/bin/env bash
# 모듈 44 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name karpenter 2>/dev/null || true

echo "모듈 44 정리 완료"
echo "★ 기억할 것: Karpenter는 Pod 제약을 역방향으로 풀어 노드를 빚습니다 — 그 자유는 워크로드의 중단 내성(PDB)이라는 규율을 요구한다"
