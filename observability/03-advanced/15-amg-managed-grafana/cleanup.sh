#!/usr/bin/env bash
# 모듈 15 정리 — ⚠️ AMG 워크스페이스 삭제 (사용자당 과금 차단)
set -euo pipefail

REGION=${REGION:-ap-northeast-2}

if [ -n "${AMG_ID:-}" ]; then
  aws grafana delete-workspace --region "$REGION" --workspace-id "$AMG_ID" 2>/dev/null || true
else
  AMG_ID=$(aws grafana list-workspaces --region "$REGION" \
    --query "workspaces[?name=='obs-curriculum'].id" --output text 2>/dev/null || true)
  [ -n "$AMG_ID" ] && aws grafana delete-workspace --region "$REGION" --workspace-id "$AMG_ID" 2>/dev/null || true
fi

rm -f /tmp/push-dashboard.sh 2>/dev/null || true

echo "모듈 15 정리 완료 — AMG 워크스페이스 삭제"
echo "★ 기억할 것: AWS는 물리를 맡고 규약은 남습니다 — as code(Git이 진실)·알림 일원화는 관리형에서도 우리 몫"
