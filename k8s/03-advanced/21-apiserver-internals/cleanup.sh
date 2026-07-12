#!/usr/bin/env bash
# 모듈 21 정리 — audit 로깅 비활성화 (CloudWatch 비용 차단)
set -euo pipefail
kubectl delete deployment obs --ignore-not-found
kubectl delete pod watch-me --ignore-not-found
kubectl delete secret audit-bait --ignore-not-found

aws eks update-cluster-config --name k8s-study --region "${AWS_REGION:-ap-northeast-2}" \
  --logging '{"clusterLogging":[{"types":["audit","authenticator"],"enabled":false}]}' 2>/dev/null \
  || echo "(로깅 변경 진행 중이거나 이미 꺼짐)"
echo "CloudWatch 로그 그룹 보관 데이터는 남아 있음 — 완전 삭제:"
echo "  aws logs delete-log-group --log-group-name /aws/eks/k8s-study/cluster --region ap-northeast-2"
echo "모듈 21 정리 완료"
