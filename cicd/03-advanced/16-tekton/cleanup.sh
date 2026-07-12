#!/usr/bin/env bash
# 모듈 16 정리 — Tekton 리소스, Triggers, Pipeline 컴포넌트
set -euo pipefail

kubectl delete namespace tektonlab --ignore-not-found

# Triggers, Pipelines 제거
kubectl delete -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml 2>/dev/null || true
kubectl delete -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml 2>/dev/null || true
kubectl delete -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml 2>/dev/null || true

echo "모듈 16 정리 완료"
echo "잔여 CI Pod 확인:"
kubectl get pods -A 2>/dev/null | grep -iE "tekton|taskrun|pipelinerun" || echo "  없음"
