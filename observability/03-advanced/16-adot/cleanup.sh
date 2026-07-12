#!/usr/bin/env bash
# 모듈 16 정리 — ⚠️ ADOT·IRSA·EMF 로그 그룹 정리
set -euo pipefail

CLUSTER=${CLUSTER:-my-eks}
REGION=${REGION:-ap-northeast-2}

kubectl delete namespace shop --ignore-not-found --wait=false 2>/dev/null || true
kubectl -n observability delete opentelemetrycollector adot 2>/dev/null || true
kubectl delete namespace observability --ignore-not-found --wait=false 2>/dev/null || true

aws eks delete-addon --cluster-name "$CLUSTER" --region "$REGION" --addon-name adot 2>/dev/null || true

eksctl delete iamserviceaccount --cluster "$CLUSTER" --region "$REGION" \
  --namespace observability --name adot-collector 2>/dev/null || true

aws logs delete-log-group --region "$REGION" --log-group-name /adot/emf/shop 2>/dev/null || true

echo "모듈 16 정리 완료 — ADOT 애드온·Collector·IRSA·EMF 로그 그룹 삭제"
echo "(17에서 X-Ray 실습을 이어가려면 ADOT를 유지하고 이 스크립트는 17 이후에 실행)"
echo "★ 기억할 것: 수집 한 번, 목적지 셋 — 그리고 접합부(전파 겸용·샘플링 단일화)가 이기종 혼재의 열쇠"
