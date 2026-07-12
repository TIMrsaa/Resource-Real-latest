#!/usr/bin/env bash
# 모듈 40 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name strimzi 2>/dev/null || true

echo "모듈 40 정리 완료"
echo "★ 기억할 것: Strimzi는 Kafka를 운영하고(39의 Rook과 동형), CloudEvents는 이벤트를 통일합니다(06·03과 계열)"
