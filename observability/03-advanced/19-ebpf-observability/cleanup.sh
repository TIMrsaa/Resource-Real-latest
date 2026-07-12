#!/usr/bin/env bash
# 모듈 19 정리 — kind 클러스터
set -euo pipefail

kind delete cluster --name ebpf 2>/dev/null || true
rm -f /tmp/kind-cilium.yaml 2>/dev/null || true

echo "모듈 19 정리 완료"
echo "★ 기억할 것: eBPF는 구간의 사실(즉시·전체·무계측), OTel은 여정과 맥락 — 관측 성숙도는 영토 지도의 정확도다"
