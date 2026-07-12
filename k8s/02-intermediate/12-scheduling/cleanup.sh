#!/usr/bin/env bash
# 모듈 12 정리 — taint/label/우선순위 실험물 원복
set -euo pipefail
kubectl delete deployment spread-demo filler crowd ml-job --ignore-not-found
kubectl delete pod vip on-ssd on-nvme prefer-ssd --ignore-not-found
kubectl delete priorityclass vip peasant --ignore-not-found

# 노드 taint/label/cordon 원복
for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl uncordon "$n" 2>/dev/null || true
  kubectl taint node "$n" team=ml:NoSchedule- 2>/dev/null || true
  kubectl taint node "$n" evacuate=now:NoExecute- 2>/dev/null || true
  kubectl label node "$n" disktype- 2>/dev/null || true
done
echo "모듈 12 정리 완료"
