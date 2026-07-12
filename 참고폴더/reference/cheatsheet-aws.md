# AWS CLI 치트시트 (EKS 학습용)

## 자격증명 / 정체

```bash
aws configure                                   # 자격증명 등록
aws configure list
aws sts get-caller-identity                     # 현재 IAM 정체
aws sts get-caller-identity --query Account --output text
```

## EKS

```bash
aws eks list-clusters --region ap-northeast-2
aws eks describe-cluster --name eks-study --query 'cluster.{status:status,version:version,endpoint:endpoint}'
aws eks update-kubeconfig --name eks-study --region ap-northeast-2
aws eks list-nodegroups --cluster-name eks-study
aws eks describe-nodegroup --cluster-name eks-study --nodegroup-name workers
```

## ECR

```bash
# 로그인
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# 리포 생성/조회
aws ecr create-repository --repository-name eks-study/order-service
aws ecr describe-repositories
aws ecr describe-images --repository-name eks-study/order-service
aws ecr delete-repository --repository-name eks-study/order-service --force
```

## EC2

```bash
# 실행 중 인스턴스
aws ec2 describe-instances \
  --query 'Reservations[].Instances[?State.Name==`running`].[InstanceId,InstanceType,PrivateIpAddress]' \
  --output table

# Spot 인스턴스 가격
aws ec2 describe-spot-price-history \
  --instance-types t3.medium --product-descriptions "Linux/UNIX" \
  --max-items 5

# 인스턴스 종료
aws ec2 terminate-instances --instance-ids i-xxx
```

## VPC / 네트워킹

```bash
aws ec2 describe-vpcs --query 'Vpcs[].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxx" \
  --query 'Subnets[].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch]' --output table
aws ec2 describe-nat-gateways --filter Name=state,Values=available
aws ec2 describe-addresses
```

## IAM

```bash
aws iam list-users
aws iam list-roles --query 'Roles[?starts_with(RoleName,`eks-`)].[RoleName,Arn]' --output table
aws iam list-policies --scope Local --query 'Policies[].[PolicyName,Arn]' --output table

# Trust policy 보기
aws iam get-role --role-name <role> --query 'Role.AssumeRolePolicyDocument'
```

## CloudWatch Logs

```bash
aws logs describe-log-groups --query 'logGroups[?starts_with(logGroupName,`/aws/eks`)].logGroupName'
aws logs tail /aws/eks/eks-study/cluster --follow              # tail
aws logs tail /aws/containerinsights/eks-study/application --since 5m
```

## SQS

```bash
aws sqs create-queue --queue-name payments
aws sqs list-queues
aws sqs send-message --queue-url <url> --message-body '{"order_id":"o1"}'
aws sqs receive-message --queue-url <url>
aws sqs get-queue-attributes --queue-url <url> --attribute-names All
aws sqs delete-queue --queue-url <url>
```

## Cost Explorer / Budgets

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-7d +%F),End=$(date -u +%F) \
  --granularity DAILY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)
```

## 잔존 리소스 점검 (cleanup 전 필수)

```bash
# 한 번에 실행 가능한 종합 점검
echo "=== Running EC2 ===" && aws ec2 describe-instances --query 'Reservations[].Instances[?State.Name==`running`].[InstanceId,InstanceType]' --output text
echo "=== EKS ===" && aws eks list-clusters --output text
echo "=== LB ===" && aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text
echo "=== Unattached EBS ===" && aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text
echo "=== Idle EIP ===" && aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].PublicIp' --output text
echo "=== NAT GW ===" && aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId' --output text
```
