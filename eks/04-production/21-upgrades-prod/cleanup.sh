#!/usr/bin/env bash
# 모듈 21 정리 — 실험 노드그룹 2종과 워크로드
set -euo pipefail
export AWS_REGION=ap-northeast-2
CLUSTER=k8s-study

kubectl delete pdb fleet-app-pdb --ignore-not-found
kubectl delete deployment fleet-app --ignore-not-found

for ng in blue-lab green-lab; do
  eksctl delete nodegroup --cluster $CLUSTER --region $AWS_REGION --name $ng --wait 2>/dev/null || true
done

# cordon 잔재 원복
for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl uncordon "$n" 2>/dev/null || true
done

echo "모듈 21 정리 완료 — eksctl get nodegroup으로 잔재 확인"
