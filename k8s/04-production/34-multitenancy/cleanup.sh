#!/usr/bin/env bash
# 모듈 34 정리 — 테넌트 ns, VAP, 노드 taint/label 원복
set -euo pipefail

kubectl delete validatingadmissionpolicybinding tenant-toleration-guard --ignore-not-found
kubectl delete validatingadmissionpolicy tenant-toleration-guard --ignore-not-found

kubectl delete namespace team-rocket team-galaxy --ignore-not-found

# 어느 노드에 달았는지 기억에 의존하지 않도록 전 노드 순회
for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl taint node "$n" tenant=team-rocket:NoSchedule- 2>/dev/null || true
  kubectl label node "$n" tenant- 2>/dev/null || true
done

echo "모듈 34 정리 완료 — get nodes -L tenant로 라벨 잔재 없는지 확인"
