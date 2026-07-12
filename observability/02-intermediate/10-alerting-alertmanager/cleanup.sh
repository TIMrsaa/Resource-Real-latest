#!/usr/bin/env bash
# 모듈 10 정리 — kind 클러스터 + 임시 values
set -euo pipefail

kind delete cluster --name alerts 2>/dev/null || true
rm -f /tmp/am-values.yaml 2>/dev/null || true

echo "모듈 10 정리 완료"
echo "★ 기억할 것: 알림의 최대 적은 침묵이 아니라 소음입니다 — 소음은 진짜를 가립니다 (3심사·for·그룹핑·억제, 그리고 삭제의 용기)"
