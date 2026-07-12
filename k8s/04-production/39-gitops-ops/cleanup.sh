#!/usr/bin/env bash
# 모듈 39 정리
set -euo pipefail
# Application 먼저 (cascade로 guestbook 리소스 정리)
kubectl delete application guestbook -n argocd --ignore-not-found
sleep 5
kubectl delete namespace guestbook --ignore-not-found
# ArgoCD 본체 (cicd 파트에서 다시 설치하므로 제거 — 유지하고 싶으면 이 두 줄 주석)
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --ignore-not-found 2>/dev/null || true
kubectl delete namespace argocd --ignore-not-found
# port-forward 잔여 프로세스
pkill -f "port-forward svc/argocd-server" 2>/dev/null || true
echo "모듈 39 정리 완료"
