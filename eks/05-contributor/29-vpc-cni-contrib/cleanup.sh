#!/usr/bin/env bash
# 모듈 29 정리 — 클러스터 리소스 없음 (로컬 개발)
set -euo pipefail

# ⚠️ 안전 확인: 혹시라도 커스텀 CNI 이미지가 배포됐는지
IMG=$(kubectl get ds aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")
case "$IMG" in
  *amazon-k8s-cni*|"") echo "aws-node 이미지 정상: ${IMG:-확인불가}" ;;
  *) echo "🚨 aws-node가 비표준 이미지($IMG) — 즉시 애드온 재적용으로 복구:"
     echo "   aws eks update-addon --cluster-name k8s-study --addon-name vpc-cni --resolve-conflicts OVERWRITE" ;;
esac

echo "모듈 29 정리 완료 — 소스(~/cni)는 보존"
echo "🎓 eks 파트 29개 모듈 완주. 다음: cicd / cncf 파트"
