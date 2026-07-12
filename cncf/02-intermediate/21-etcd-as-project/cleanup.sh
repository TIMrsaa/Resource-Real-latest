#!/usr/bin/env bash
# 모듈 21 정리 — kind 클러스터, 실습용 etcd 컨테이너
set -euo pipefail

pkill -f "port-forward.*2381" 2>/dev/null || true
docker rm -f etcd-lab 2>/dev/null || true
kind delete cluster --name etcd 2>/dev/null || true

echo "모듈 21 정리 완료 — 중급 심층 트랙(11~21) 종료"
echo "★ 기억할 것: etcd는 조용히 나빠지고, 조용히 백업을 망가뜨린다"
