#!/usr/bin/env bash
# 모듈 15 정리 — kind 클러스터, 로컬 차트
set -euo pipefail

kind delete cluster --name helm 2>/dev/null || true
rm -rf ~/cncf-lab/helm
rm -f /tmp/rendered.yaml /tmp/out.yaml /tmp/config.bak

echo "모듈 15 정리 완료"
echo "★ 기억할 것: Helm을 이해한다는 것은 '누가 무엇을 소유하는가'를 설계하는 일"
