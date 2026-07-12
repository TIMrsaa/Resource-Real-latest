#!/usr/bin/env bash
# 모듈 26 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name ctrd 2>/dev/null || true

echo "모듈 26 정리 완료"
echo "★ 기억할 것: kubectl로 안 보이는 문제가 있고, 그 아래에 crictl·ctr의 세계가 있다"
