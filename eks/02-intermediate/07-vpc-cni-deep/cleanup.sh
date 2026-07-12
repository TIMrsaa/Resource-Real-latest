#!/usr/bin/env bash
# 모듈 07 정리 — 노드 수 원복 (prefix delegation 설정은 유지 — 신규 표준)
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}
CLUSTER=${CLUSTER:-k8s-study}
kubectl delete deployment ip-eater --ignore-not-found
NG=$(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$AWS_REGION" --query 'nodegroups[0]' --output text)
CUR=$(aws eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name "$NG" --region "$AWS_REGION" --query 'nodegroup.scalingConfig.desiredSize' --output text)
if [ "$CUR" -gt 2 ]; then
  aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NG" --region "$AWS_REGION" \
    --scaling-config desiredSize=2
  echo "노드 수 2로 원복 요청"
fi
echo "모듈 07 정리 완료"
