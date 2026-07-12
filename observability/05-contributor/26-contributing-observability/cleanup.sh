#!/usr/bin/env bash
# 모듈 26 정리 — kind 클러스터 + 빌드 산출물 (레포 클론은 계속 쓸 수 있어 보존)
set -euo pipefail

kind delete cluster --name contrib 2>/dev/null || true
# my-exporter·my-otelcol·fluent-bit 클론은 기여 작업의 자산 — 직접 정리 판단

echo "모듈 26 정리 완료 — Part 5(observability) 전체 수료"
echo "★ 기억할 것: 졸업장은 자격증이 아니라 기여 이력입니다 — 신호를 소비하는 사람에서, 신호의 도구를 만드는 사람으로. 생태계에서 만나자."
