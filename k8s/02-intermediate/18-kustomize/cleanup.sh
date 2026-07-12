#!/usr/bin/env bash
# 모듈 18 정리
set -euo pipefail
kubectl delete namespace kz-dev kz-prod --ignore-not-found
echo "로컬 ~/kustomize-lab 은 학습 산출물 — 직접 판단해 삭제: rm -rf ~/kustomize-lab"
echo "모듈 18 정리 완료"
