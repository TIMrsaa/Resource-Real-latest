#!/usr/bin/env bash
set -euo pipefail

echo "▶ 모듈 09 (MSA) 정리"

kubectl delete servicemonitor -n monitoring order-msa --ignore-not-found
kubectl delete ns order --ignore-not-found
echo "  → ALB 삭제 진행 중 (45초 대기)..."
sleep 45

# 잔존 ALB 확인
echo ""
echo "잔존 ALB 점검:"
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?starts_with(LoadBalancerName,`k8s-`)].LoadBalancerName' --output text

echo ""
echo "✅ Module 09 정리 완료"
echo ""
echo "==== Part 2 종료 ===="
echo ""
echo "Part 2 학습이 모두 끝났다면 클러스터/관측 스택을 정리하세요:"
echo ""
echo "  # 관측 스택 (Module 08)"
echo "  helm uninstall kps -n monitoring 2>/dev/null"
echo "  kubectl delete pvc -n monitoring -l release=kps 2>/dev/null"
echo "  kubectl delete ns monitoring amazon-cloudwatch 2>/dev/null"
echo "  eksctl delete addon --name amazon-cloudwatch-observability --cluster eks-study --region ap-northeast-2 2>/dev/null"
echo ""
echo "  # CloudWatch Logs Group (비용 정지)"
echo "  for lg in \$(aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/eks-study/ --query 'logGroups[].logGroupName' --output text); do"
echo "    aws logs delete-log-group --log-group-name \"\$lg\""
echo "  done"
echo ""
echo "  # 클러스터 자체 삭제 (Part 3 시작 전이면 유지해도 됨)"
echo "  eksctl delete cluster --name eks-study --region ap-northeast-2"
