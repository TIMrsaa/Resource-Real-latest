#!/usr/bin/env bash
# 모듈 35 정리 — 실습 워크로드/PDB 제거, cordon 원복
set -euo pipefail

kubectl delete pdb ha-app-pdb --ignore-not-found
kubectl delete deployment ha-app --ignore-not-found

# drain/cordon 실험 후 남은 SchedulingDisabled 원복
for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl uncordon "$n" 2>/dev/null || true
done

rm -rf ~/upgrade-lab

echo "모듈 35 정리 완료 — kubectl get nodes에서 SchedulingDisabled 없는지 확인"
