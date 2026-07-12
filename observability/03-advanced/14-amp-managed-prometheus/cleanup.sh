#!/usr/bin/env bash
# 모듈 14 정리 — ⚠️ AMP 워크스페이스·IRSA 삭제 (비용 차단)
set -euo pipefail

CLUSTER=${CLUSTER:-my-eks}
REGION=${REGION:-ap-northeast-2}

# remote_write 제거 (helm 값 원복 — 로컬 스택은 유지 시)
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --reuse-values \
  --set prometheus.prometheusSpec.remoteWrite=null \
  --set prometheus.prometheusSpec.serviceAccountName="" 2>/dev/null || true

# AMP 룰·워크스페이스 삭제
if [ -n "${WS_ID:-}" ]; then
  aws amp delete-rule-groups-namespace --region "$REGION" \
    --workspace-id "$WS_ID" --name curriculum-rules 2>/dev/null || true
  aws amp delete-workspace --region "$REGION" --workspace-id "$WS_ID" 2>/dev/null || true
else
  echo "WS_ID 미설정 — 콘솔/CLI로 워크스페이스(alias: obs-curriculum) 삭제 확인 필요"
  aws amp list-workspaces --region "$REGION" --alias obs-curriculum \
    --query 'workspaces[].workspaceId' --output text 2>/dev/null || true
fi

# IRSA 삭제
eksctl delete iamserviceaccount --cluster "$CLUSTER" --region "$REGION" \
  --namespace monitoring --name amp-irsa 2>/dev/null || true

rm -f /tmp/amp-rules.yaml /tmp/amp-values.yaml 2>/dev/null || true

echo "모듈 14 정리 완료 — AMP 워크스페이스·룰·IRSA 삭제"
echo "★ 기억할 것: 절단선은 수집과 저장 사이 — 체계는 우리 것, 물리는 관리형. 그리고 '평가 주체'를 항상 명시하라"
