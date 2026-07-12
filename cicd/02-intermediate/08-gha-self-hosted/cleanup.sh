#!/usr/bin/env bash
# 모듈 08 정리 — ARC(러너 Pod가 노드를 요구하므로 과금), 저장소
set -euo pipefail

# 러너 스케일셋 → 컨트롤러 순서로 (러너 Pod 먼저 정리)
helm uninstall eks-runners -n arc-runners 2>/dev/null || true
kubectl delete networkpolicy runner-egress-lockdown -n arc-runners 2>/dev/null || true
kubectl delete secret arc-gh-app -n arc-runners 2>/dev/null || true
helm uninstall arc -n arc-systems 2>/dev/null || true
kubectl delete namespace arc-runners arc-systems --ignore-not-found

# 남은 러너 Pod가 만든 노드는 Karpenter가 회수 (eks 17). 확인:
echo "러너 잔재 Pod 확인:"
kubectl get pods -A 2>/dev/null | grep -i runner || echo "  없음"

cd ~/ci-lab/arc 2>/dev/null && {
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
  [ -n "$REPO" ] && gh repo delete "$REPO" --yes 2>/dev/null || true
  cd ~
}
rm -rf ~/ci-lab/arc

echo "모듈 08 정리 완료"
echo "⚠️  GitHub App은 수동 삭제 (Settings → Developer settings → GitHub Apps)"
echo "⚠️  Karpenter가 만든 CI 노드가 회수됐는지 kubectl get nodes로 확인"
