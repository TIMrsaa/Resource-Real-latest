#!/usr/bin/env bash
# 모듈 30 정리
set -euo pipefail
kubectl delete website --all --ignore-not-found 2>/dev/null || true
kubectl delete crd websites.platform.example.com --ignore-not-found
# make deploy를 했다면: (프로젝트 디렉터리에서) make undeploy
echo "로컬 ~/website-operator 는 학습 산출물 — 기여자 트랙에서 재활용 가치 있음. 보존 권장"
echo "모듈 30 정리 완료"
