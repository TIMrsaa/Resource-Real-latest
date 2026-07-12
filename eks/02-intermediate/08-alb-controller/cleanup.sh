#!/usr/bin/env bash
# 모듈 08 정리 — LB 잔존 = 과금! Ingress/Service 먼저, 컨트롤러는 유지(이후 모듈 사용)
set -euo pipefail
AWS_REGION=${AWS_REGION:-ap-northeast-2}
kubectl delete targetgroupbinding shop-tgb -n web --ignore-not-found 2>/dev/null || true
kubectl delete ingress shop api -n web --ignore-not-found
kubectl delete svc shop-nlb -n web --ignore-not-found
sleep 30    # 컨트롤러가 ALB/NLB 삭제할 시간
kubectl delete namespace web --ignore-not-found
# 수동 생성한 대상그룹
TG=$(aws elbv2 describe-target-groups --region "$AWS_REGION" \
  --names manual-shop-tg --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null) || true
[ -n "${TG:-}" ] && [ "$TG" != "None" ] && aws elbv2 delete-target-group --target-group-arn "$TG" --region "$AWS_REGION"
# 잔존 LB 확인 (있으면 과금 중!)
aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query 'LoadBalancers[].{name:LoadBalancerName,type:Type}' --output table
rm -f iam_policy.json
echo "모듈 08 정리 완료 — 위 표에 예상 밖 LB가 있으면 수동 확인!"
echo "(LB 컨트롤러는 14/15에서 계속 사용 — 유지)"
