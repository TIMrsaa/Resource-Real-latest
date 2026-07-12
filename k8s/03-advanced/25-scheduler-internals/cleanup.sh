#!/usr/bin/env bash
# 모듈 25 정리
set -euo pipefail
kubectl delete pod by-default by-cost placed waiter multi-reject --ignore-not-found
for i in 1 2 3; do kubectl delete pod spread-$i pack-$i --ignore-not-found; done
kubectl delete namespace scheduler-lab --ignore-not-found
kubectl delete clusterrolebinding cost-scheduler-as-kube-scheduler cost-scheduler-as-volume-scheduler cost-scheduler-extra --ignore-not-found
for n in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl taint node "$n" exam=filter:NoSchedule- 2>/dev/null || true
done
echo "모듈 25 정리 완료"
