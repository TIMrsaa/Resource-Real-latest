#!/usr/bin/env bash
# 모듈 06 정리 — LB 만드는 것들부터 역순 철거
set -euo pipefail
kubectl delete httproute store-route store-beta-route --ignore-not-found
kubectl delete gateway main-gw --ignore-not-found
kubectl delete ingress store store-canary --ignore-not-found 2>/dev/null || true
helm uninstall ngf -n nginx-gateway 2>/dev/null || true
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
kubectl delete namespace nginx-gateway ingress-nginx --ignore-not-found
kubectl delete -f manifests/backends.yaml --ignore-not-found
echo "LB 잔존 확인:"
kubectl get svc -A 2>/dev/null | grep LoadBalancer || echo "  LB 없음 - OK"
echo "모듈 06 정리 완료"
