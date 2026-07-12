#!/usr/bin/env bash
# 모듈 23 정리 — 웹훅 설정 먼저! (남으면 Pod 생성 방해)
set -euo pipefail
kubectl delete validatingwebhookconfiguration team-label-webhook --ignore-not-found
kubectl delete validatingadmissionpolicybinding require-image-tag-warn require-cost-label-binding max-replicas-binding --ignore-not-found
kubectl delete validatingadmissionpolicy require-image-tag require-cost-label max-replicas --ignore-not-found
kubectl delete namespace vap-lab webhook hook-target --ignore-not-found
rm -rf ~/webhook-lab
echo "모듈 23 정리 완료"
