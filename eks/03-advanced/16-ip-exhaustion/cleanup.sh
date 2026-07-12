#!/usr/bin/env bash
# 모듈 16 정리 — 조립의 역순 해체: 노드그룹 → env 원복 → ENIConfig → 서브넷 → CIDR
set -euo pipefail
export AWS_REGION=ap-northeast-2
CLUSTER=k8s-study
VPC=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)

kubectl delete pod migrant --ignore-not-found

# 1) 실험 노드그룹 (가장 오래 걸림 — 먼저 시작)
eksctl delete nodegroup --cluster $CLUSTER --region $AWS_REGION --name ip-lab --wait 2>/dev/null || true

# 2) 전역 스위치 원복 (★ 이 랩의 계약)
kubectl set env ds aws-node -n kube-system \
  AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG- ENI_CONFIG_LABEL_DEF- 2>/dev/null || true
kubectl rollout status ds/aws-node -n kube-system --timeout=120s || true

# 3) ENIConfig
kubectl delete eniconfig --all --ignore-not-found

# 4) Pod 서브넷 (Name 태그로 식별)
for s in $(aws ec2 describe-subnets --region $AWS_REGION \
  --filters Name=vpc-id,Values=$VPC Name=tag:Name,Values=podnet-iplab \
  --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --subnet-id "$s" --region $AWS_REGION
done

# 5) secondary CIDR 해제 (서브넷이 다 사라져야 가능)
ASSOC=$(aws ec2 describe-vpcs --vpc-ids $VPC --region $AWS_REGION \
  --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='100.64.0.0/16'].AssociationId" --output text)
[ -n "$ASSOC" ] && aws ec2 disassociate-vpc-cidr-block --association-id $ASSOC --region $AWS_REGION

rm -f ip-budget.sh

echo "모듈 16 정리 완료 — describe-vpcs로 100.64 대역 해제 확인, aws-node env 원복 확인"
