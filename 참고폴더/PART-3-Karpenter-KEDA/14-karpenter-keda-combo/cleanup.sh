#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
QUEUE_URL=$(aws sqs get-queue-url --queue-name eks-study-payments --query QueueUrl --output text 2>/dev/null || true)

echo "▶ 모듈 14 정리"

# ScaledObject 제거 → KEDA 가 더 이상 Pod 안 만듦
kubectl delete -n order scaledobject payment-service --ignore-not-found

# Pod 0 으로 줄이기
kubectl scale deploy/payment-service -n order --replicas=0

echo "  → Pod 종료 + Karpenter 노드 회수 대기 (60초)..."
sleep 60

# 큐 정리
if [[ -n "${QUEUE_URL}" ]]; then
  aws sqs purge-queue --queue-url "$QUEUE_URL" 2>/dev/null || true
  echo "  → SQS 큐 비움: $QUEUE_URL"
fi

echo ""
echo "잔존 Karpenter 노드 점검:"
kubectl get nodes -l managed-by=karpenter

echo ""
echo "✅ Module 14 정리 완료"
