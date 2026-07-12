#!/usr/bin/env bash
# 모듈 05 정리 — kind 클러스터, CSI 클론
set -euo pipefail

kind delete cluster --name csi 2>/dev/null || true
rm -rf ~/cncf-lab/csi-hostpath

echo "모듈 05 정리 완료"
