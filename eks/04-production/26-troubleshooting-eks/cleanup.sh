#!/usr/bin/env bash
# 모듈 26 정리 — 진단 도구와 실험 ns (수집 결과물은 남깁니다)
set -euo pipefail

kubectl delete namespace tslab --ignore-not-found
kubectl delete pod toolbox --ignore-not-found

# kubectl debug 잔재
for p in $(kubectl get pods -A --no-headers 2>/dev/null | awk '/node-debugger/{print $2" -n "$1}'); do
  kubectl delete pod $p --ignore-not-found 2>/dev/null || true
done

rm -f toolbox.yaml
# collect.sh와 incident-* 디렉터리는 의도적으로 보존 (팀 자산)

echo "모듈 26 정리 완료 — 실무 트랙(21~26) 졸업. collect.sh는 보존됨"
