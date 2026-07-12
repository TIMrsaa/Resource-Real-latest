#!/usr/bin/env bash
# 모듈 24 정리
set -euo pipefail
kubectl delete deployment ssa-demo --ignore-not-found
kubectl delete cm blog-config guarded --ignore-not-found 2>/dev/null || true
# guarded가 finalizer로 Terminating이면 제거
kubectl patch cm guarded --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
kubectl delete ws --all --ignore-not-found 2>/dev/null || true
kubectl delete crd websites.platform.example.com --ignore-not-found
rm -f /tmp/team-a.yaml /tmp/team-b.yaml
echo "모듈 24 정리 완료"
