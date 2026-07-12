#!/usr/bin/env bash
# 모듈 17 정리 — NodePool 삭제(=노드 회수)부터, EC2 잔재 확인까지
set -euo pipefail
export AWS_REGION=ap-northeast-2
CLUSTER=k8s-study
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

kubectl delete deployment inflate --ignore-not-found

# 1) NodePool/EC2NodeClass 삭제 → Karpenter가 자기 노드를 drain 후 회수
kubectl delete nodepool lab --ignore-not-found
kubectl delete ec2nodeclass default --ignore-not-found
echo "노드 회수 대기..."
for i in $(seq 1 30); do
  LEFT=$(kubectl get nodeclaims --no-headers 2>/dev/null | wc -l)
  [ "$LEFT" -eq 0 ] && break; sleep 10
done

# 2) 컨트롤러 제거
helm uninstall karpenter -n karpenter 2>/dev/null || true
kubectl delete namespace karpenter --ignore-not-found

# 3) IAM/배선 해체
eksctl delete podidentityassociation --cluster $CLUSTER --region $AWS_REGION \
  --namespace karpenter --service-account-name karpenter 2>/dev/null || true
aws iam detach-role-policy --role-name KarpenterControllerRole-$CLUSTER \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/KarpenterControllerPolicy-$CLUSTER 2>/dev/null || true
aws iam delete-role --role-name KarpenterControllerRole-$CLUSTER 2>/dev/null || true
eksctl delete accessentry --cluster $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/KarpenterNodeRole-$CLUSTER 2>/dev/null || true

# 4) CloudFormation (노드 역할·정책·SQS 큐)
aws cloudformation delete-stack --stack-name Karpenter-$CLUSTER --region $AWS_REGION

# 5) discovery 태그 회수
SUBNETS=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
SG=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 delete-tags --region $AWS_REGION --resources $SUBNETS $SG \
  --tags Key=karpenter.sh/discovery 2>/dev/null || true

rm -f karpenter-cfn.yaml kp-trust.json

# 6) 최종 검증 — Karpenter 태그가 붙은 EC2가 남았는가 (남았다면 수동 종료: 과금!)
aws ec2 describe-instances --region $AWS_REGION \
  --filters "Name=tag:karpenter.sh/nodepool,Values=*" "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text
echo "모듈 17 정리 완료 — 위에 인스턴스 ID가 출력됐다면 수동 종료 필요"
