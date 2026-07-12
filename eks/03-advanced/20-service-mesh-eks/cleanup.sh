#!/usr/bin/env bash
# 모듈 20 정리 — 메시 CRD/워크로드 → istiod 완전 제거
set -euo pipefail

kubectl delete pod outsider --ignore-not-found
kubectl delete namespace meshlab --ignore-not-found

# Istio 완전 제거 (CRD 포함 — purge)
istioctl uninstall --purge -y 2>/dev/null || echo "istioctl 없음 — istio-system 수동 확인"
kubectl delete namespace istio-system --ignore-not-found

# 주입 웹훅 잔재 확인 (남으면 이후 모든 Pod 생성에 영향!)
kubectl get mutatingwebhookconfigurations 2>/dev/null | grep istio || echo "istio 웹훅 잔재 없음"

echo "모듈 20 정리 완료 — 고급 트랙(13~20) 졸업"
