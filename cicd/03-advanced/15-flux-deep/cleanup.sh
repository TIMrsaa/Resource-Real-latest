#!/usr/bin/env bash
# 모듈 15 정리 — Flux 리소스, 워크로드, Flux 컴포넌트, config repo
set -euo pipefail

# 이미지 자동화 리소스
flux delete image update demo --silent 2>/dev/null || true
flux delete image policy demo --silent 2>/dev/null || true
flux delete image repository demo --silent 2>/dev/null || true

# Kustomization/source (prune으로 워크로드 정리)
flux delete kustomization demo --silent 2>/dev/null || true
flux delete kustomization demo2 --silent 2>/dev/null || true
flux delete source git demo --silent 2>/dev/null || true
sleep 10
kubectl delete namespace flux-demo --ignore-not-found

# Flux 제거
flux uninstall --silent 2>/dev/null || kubectl delete namespace flux-system --ignore-not-found

cd ~/ci-lab/flux 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/flux

echo "모듈 15 정리 완료"
