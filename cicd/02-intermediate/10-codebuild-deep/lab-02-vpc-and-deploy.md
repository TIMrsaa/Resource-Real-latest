# Lab 02 — VPC 빌드와 EKS 배포

CodeBuild가 프라이빗 리소스에 접근하고(VPC 구성), 서비스 역할로 ECR에 밀고 EKS에 배포하는 경로를 만듭니다. eks 파트의 지식(NAT, access entry, VPC 엔드포인트)이 여기서 회수됩니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cd ~/ci-lab/cbuild
```

## Step 1. ECR + 이미지 빌드 buildspec

```bash
aws ecr create-repository --repository-name cb-lab-app --region $AWS_REGION \
  --image-tag-mutability IMMUTABLE >/dev/null 2>&1 || true

cat > Dockerfile <<'EOF'
FROM public.ecr.aws/docker/library/python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "-c", "print('ok')"]
EOF

cat > buildspec.yml <<'EOF'
version: 0.2
env:
  variables:
    ECR: ACCOUNT.dkr.ecr.REGION.amazonaws.com/cb-lab-app
phases:
  pre_build:
    commands:
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin ${ECR%/*}
      - TAG=${CODEBUILD_RESOLVED_SOURCE_VERSION:-manual}
  build:
    commands:
      - docker build -t $ECR:${TAG:0:12} .
  post_build:
    commands:
      - docker push $ECR:${TAG:0:12}
      - echo "배포 참조 - 다이제스트(04):"
      - aws ecr describe-images --repository-name cb-lab-app --region $AWS_DEFAULT_REGION --image-ids imageTag=${TAG:0:12} --query 'imageDetails[0].imageDigest' --output text
EOF
sed -i "s/ACCOUNT/$ACCOUNT_ID/; s/REGION/$AWS_REGION/" buildspec.yml
git add -A && git commit -qm "feat: ECR build" && git push -q 2>/dev/null || true
```

## Step 2. 서비스 역할에 ECR 권한 (최소 — theory §5)

```bash
aws iam put-role-policy --role-name cb-lab-role --policy-name ecr --policy-document "{
  \"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":\"ecr:GetAuthorizationToken\",\"Resource\":\"*\"},
    {\"Effect\":\"Allow\",
     \"Action\":[\"ecr:BatchCheckLayerAvailability\",\"ecr:PutImage\",\"ecr:InitiateLayerUpload\",\"ecr:UploadLayerPart\",\"ecr:CompleteLayerUpload\",\"ecr:BatchGetImage\"],
     \"Resource\":\"arn:aws:ecr:$AWS_REGION:$ACCOUNT_ID:repository/cb-lab-app\"}
  ]}"

# Docker 빌드에는 privileged 필요 → 프로젝트에 privilegedMode
aws codebuild update-project --name cb-lab --region $AWS_REGION \
  --environment "{\"type\":\"LINUX_CONTAINER\",\"image\":\"aws/codebuild/amazonlinux2-x86_64-standard:5.0\",\"computeType\":\"BUILD_GENERAL1_SMALL\",\"privilegedMode\":true}" >/dev/null
```

> ⚠️ `privilegedMode`는 Docker 데몬을 위해 필요하지만 08의 dind 위험과 같은 성질 — 관리형이라 격리는 AWS가 주지만, 신뢰할 수 없는 코드를 이 프로젝트로 빌드하지 말 것.

## Step 3. 빌드 → ECR 푸시 확인

```bash
BID=$(aws codebuild start-build --project-name cb-lab --region $AWS_REGION --query 'build.id' --output text)
while true; do
  ST=$(aws codebuild batch-get-builds --ids $BID --region $AWS_REGION --query 'builds[0].buildStatus' --output text)
  [ "$ST" != "IN_PROGRESS" ] && break; sleep 15
done
echo "빌드: $ST"
aws ecr describe-images --repository-name cb-lab-app --region $AWS_REGION \
  --query 'imageDetails[0].{tag:imageTags[0],digest:imageDigest,pushed:imagePushedAt}' --output json
```

✅ CodeBuild가 **OIDC 없이 서비스 역할로** ECR에 밀었습니다(theory §5) — GitHub Actions(07)와 다른 인증 경로, 같은 결과.

## Step 4. EKS 배포 — access entry 매핑 (eks 02)

CodeBuild 역할이 클러스터에 `kubectl`을 쓰려면 access entry가 필요합니다:

```bash
eksctl create accessentry --cluster $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/cb-lab-role \
  --kubernetes-groups cb-deployers 2>/dev/null || echo "(이미 존재)"

# 그 그룹에 배포 권한 (RBAC — k8s 11)
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: cb-deploy, namespace: default }
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get","list","create","update","patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: cb-deploy, namespace: default }
subjects: [{ kind: Group, name: cb-deployers, apiGroup: rbac.authorization.k8s.io }]
roleRef: { kind: Role, name: cb-deploy, apiGroup: rbac.authorization.k8s.io }
EOF
```

배포 buildspec 페이즈 추가:

```bash
cat >> buildspec.yml <<'EOF'
      - |
        # EKS 배포 (개념 — 실제로는 helm/kubectl set image)
        aws eks update-kubeconfig --name k8s-study --region $AWS_DEFAULT_REGION
        kubectl get deployments -n default || echo "kubectl 접근 확인"
EOF
echo "✅ CodeBuild 역할 → access entry → RBAC 그룹 → kubectl (eks 02·k8s 11의 사슬)"
```

## Step 5. VPC 빌드 구성 — 그리고 그 대가

프라이빗 리소스 접근이 필요하다면(예: VPC 안 RDS로 마이그레이션 실행):

```bash
# 클러스터 VPC/서브넷 재사용
VPC=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
SUBNETS=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.resourcesVpcConfig.subnetIds' --output text | tr '\t' ',')
SG=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

# 서비스 역할에 ENI 생성 권한 필요 (VPC 빌드의 요구)
aws iam put-role-policy --role-name cb-lab-role --policy-name vpc --policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":["ec2:CreateNetworkInterface","ec2:DescribeNetworkInterfaces","ec2:DeleteNetworkInterface","ec2:DescribeSubnets","ec2:DescribeSecurityGroups","ec2:DescribeVpcs","ec2:CreateNetworkInterfacePermission"],
  "Resource":"*"}]}'

echo "VPC 구성 시 유의 (eks 파트 회수):"
echo "  - 빌드마다 ENI가 IP 소비 → 서브넷 IP 예산 (eks 16)"
echo "  - 프라이빗 서브넷 빌드의 외부 접근 = NAT 처리 요금 (eks 22 숨은 3대장)"
echo "  - ECR/S3 VPC 엔드포인트로 NAT 우회 (eks 22 최적화 1순위)"
# 실제 적용은 선택 (NAT 비용):
# aws codebuild update-project --name cb-lab --region $AWS_REGION \
#   --vpc-config "{\"vpcId\":\"$VPC\",\"subnets\":[\"...\"],\"securityGroupIds\":[\"$SG\"]}"
```

✅ **VPC 빌드는 "인터넷 없는 빌드"가 아니라 "NAT를 거치는 빌드"**입니다(guide). 프라이빗 접근을 얻는 대신 IP·NAT 비용을 냅니다 — 08의 self-hosted 러너 VPC 배치와 정확히 같은 거래.

## Step 6. 산출물 — CodeBuild 운영 체크리스트

```markdown
# CodeBuild 운영
- 서비스 역할: 자원 ARN 단위 최소권한 (ECR는 그 repo만)
- EKS 배포: access entry(eks 02) + RBAC 그룹(k8s 11) 매핑
- 캐시: 의존성 S3 + Docker BuildKit/ECR 레지스트리 캐시(04)
- privilegedMode: Docker 빌드에 필요하나 신뢰 코드만 (08의 dind 위험)
- VPC 빌드: 정말 프라이빗 접근이 필요할 때만
  → VPC 엔드포인트(ECR/S3/logs)로 NAT 비용 회피 (eks 22)
  → 서브넷 IP 예산 확인 (eks 16)
- 시크릿: Secrets Manager 통합(env.secrets-manager), 로그 노출 주의
```

## 정리

```bash
bash cleanup.sh
```
