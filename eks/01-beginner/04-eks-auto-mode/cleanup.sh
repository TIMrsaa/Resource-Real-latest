#!/usr/bin/env bash
# 모듈 04 정리 — Auto Mode 워크로드/풀 (노드는 수요 소멸로 자동 회수)
set -euo pipefail
kubectl delete pod small-pod auto-writer --ignore-not-found
kubectl delete deployment auto-test --ignore-not-found
kubectl delete pvc auto-data --ignore-not-found
kubectl delete storageclass auto-ebs --ignore-not-found
kubectl delete nodepool small-only --ignore-not-found 2>/dev/null || true
echo "Auto Mode 노드 회수 확인: kubectl get nodes -L eks.amazonaws.com/compute-type"
echo "(Auto Mode 기능 자체를 끄려면: aws eks update-cluster-config --compute-config '{\"enabled\":false}' ...)"
echo "모듈 04 정리 완료"
