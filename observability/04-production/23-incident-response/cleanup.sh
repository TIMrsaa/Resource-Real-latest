#!/usr/bin/env bash
# 모듈 23 정리 — kind 클러스터 + runbook 실습 파일
set -euo pipefail

kind delete cluster --name incident 2>/dev/null || true
rm -rf runbooks 2>/dev/null || true

echo "모듈 23 정리 완료"
echo "★ 기억할 것: MTTR = 기술 × 절차의 곱 — 스택의 마지막 부품은 소프트웨어가 아니라 역할·runbook·리허설이다"
