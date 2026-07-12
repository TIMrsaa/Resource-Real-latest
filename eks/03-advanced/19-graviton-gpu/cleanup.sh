#!/usr/bin/env bash
# 모듈 19 정리 — 노드그룹(과금 주범) 삭제 확인이 전부입니다
set -euo pipefail
export AWS_REGION=ap-northeast-2
CLUSTER=k8s-study

kubectl delete pod cuda-test cuda-second rightbook wrongbook --ignore-not-found 2>/dev/null || true
kubectl delete deploy pi-amd64 pi-arm64 --ignore-not-found 2>/dev/null || true
kubectl delete svc pi-amd64 pi-arm64 --ignore-not-found 2>/dev/null || true

# device plugin DS 제거
kubectl delete -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml 2>/dev/null || true

# 실험 노드그룹 삭제
for ng in graviton-lab gpu-lab; do
  eksctl delete nodegroup --cluster $CLUSTER --region $AWS_REGION --name $ng --wait 2>/dev/null || true
done

# 최종 확인 — 남은 실험 노드가 없는가
kubectl get nodes -l 'lab in (graviton, gpu)' --no-headers 2>/dev/null | wc -l | \
  xargs -I{} sh -c '[ "{}" = "0" ] && echo "모듈 19 정리 완료 — 실험 노드 잔재 없음" || echo "⚠️ 실험 노드가 남아 있음 — eksctl/콘솔 확인 (과금 중!)"'
