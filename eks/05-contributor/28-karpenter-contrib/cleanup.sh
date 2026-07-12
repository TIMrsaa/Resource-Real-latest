#!/usr/bin/env bash
# 모듈 28 정리 — 로컬 실험의 흔적과 클러스터 상태 복구
set -euo pipefail

# 실험 워크로드
kubectl delete deploy inflate --ignore-not-found

# 클러스터 Karpenter 복구 (로컬 실행 중 껐다면)
kubectl scale deploy/karpenter -n karpenter --replicas=1 2>/dev/null || true

# 로컬 소스의 replace 지시자 잔재 경고
if [ -f ~/kp/aws/go.mod ] && grep -q "replace sigs.k8s.io/karpenter" ~/kp/aws/go.mod; then
  echo "⚠️  ~/kp/aws/go.mod에 replace 지시자가 남아 있습니다 — PR 전 되돌릴 것"
fi

rm -f /tmp/karpenter-local.log
echo "모듈 28 정리 완료 — 소스(~/kp)는 보존. 로컬 컨트롤러가 떠 있다면 Ctrl-C"
