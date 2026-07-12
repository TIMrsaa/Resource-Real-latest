#!/usr/bin/env bash
# 모듈 37 정리
set -euo pipefail
# EKS 쪽 (lab-01)
kubectl delete deployment fleet --ignore-not-found 2>/dev/null || true
# 로컬 kind (lab-02) — 가짜 노드 1000개 포함 통째 삭제
kind delete cluster --name scale-lab 2>/dev/null || true
rm -f fake-node.yaml
echo "모듈 37 정리 완료"
