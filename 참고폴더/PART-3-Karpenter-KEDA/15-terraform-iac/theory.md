# 이론 — Terraform IaC for EKS

> **🌱 Terraform = "건물 설계도 + 시공 협업 룰"**
> eksctl 이 *조립식 가구 한 명이 만드는 매뉴얼* 이라면, Terraform 은 *팀이 함께 짓는 건축 도면 (state 공유)*.
> 다중 환경 / 협업 / 코드 리뷰가 시작되는 순간 eksctl 의 한계가 보이고 Terraform 이 정답이 된다.

## 1. eksctl vs Terraform

| 항목 | eksctl | Terraform |
|------|--------|-----------|
| 학습 곡선 | 낮음 | 중 |
| 단일 명령으로 클러스터 | ✓ | ✓ |
| State 관리 | CFN Stack | tfstate (S3 + DynamoDB lock 권장) |
| 다중 환경 | ClusterConfig 파일 별 | workspace + tfvars |
| K8s 리소스 적용 | 별도 (helm/kubectl) | provider 로 통합 가능 |
| 협업 | 각자 만들기 | tfstate 공유로 협업 |
| 운영 표준 | 학습/PoC | 실무 |

**실무 권장**: Terraform. 하지만 Karpenter / KEDA 같은 일부 컴포넌트는 Helm 으로 + Terraform 의 `helm_release` 리소스로 묶기.

> **🧠 "Terraform 의 진짜 가치는 *state 와 diff*"**
> 단순히 한 번 만드는 게 목적이면 어떤 도구도 비슷하다.
> 차이는 *변경 시* — Terraform 은 `plan` 으로 무엇이 어떻게 바뀔지 *코드 리뷰 가능* 한 형태로 보여준다.

## 2. 모듈 구조

```
terraform/
├── versions.tf           # provider 버전
├── variables.tf          # 입력 변수 (cluster_name, region, ...)
├── locals.tf             # 계산된 값
├── outputs.tf            # 다른 stack 이 쓸 출력
│
├── vpc.tf                # VPC + 서브넷 (terraform-aws-modules/vpc/aws)
├── eks.tf                # EKS Cluster (terraform-aws-modules/eks/aws)
├── irsa.tf               # IRSA 모듈들 (LB Controller, EBS, Karpenter)
├── karpenter.tf          # Karpenter Helm
├── keda.tf               # KEDA Helm
└── alb-controller.tf     # AWS LB Controller Helm
```

> **🧠 "파일 분리는 *의미* 단위 — `main.tf` 하나에 다 넣지 마라"**
> vpc.tf / eks.tf / irsa.tf 처럼 분리하면 PR 리뷰 시 *어느 영역 변경인지* 즉시 파악 가능.
> 하지만 너무 잘게 쪼개면 (10+ 파일) 오히려 *어디에 추가할지* 헷갈리니 7~10개가 균형점.

## 3. 핵심 모듈

### 3.1 terraform-aws-modules/vpc/aws

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "eks-study-tf"
  cidr = "10.30.0.0/16"

  azs              = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
  private_subnets  = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
  public_subnets   = ["10.30.101.0/24", "10.30.102.0/24", "10.30.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true   # 학습용 (운영은 false)
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = "eks-study-tf"
  }
}
```

### 3.2 terraform-aws-modules/eks/aws

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "eks-study-tf"
  cluster_version = "1.35"

  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    vpc-cni                = { most_recent = true }
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    aws-ebs-csi-driver     = { most_recent = true }
  }

  eks_managed_node_groups = {
    workers = {
      min_size     = 0
      max_size     = 6
      desired_size = 2

      instance_types = ["t3.medium", "t3a.medium"]
      capacity_type  = "SPOT"

      labels = {
        workload-type = "general"
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = "eks-study-tf"
  }
}
```

> **🧠 "공식 모듈 (`terraform-aws-modules/...`) 이 *수천 시간의 노하우 덩어리*"**
> 직접 작성하면 IAM Role / OIDC / addon / 노드 그룹 / IRSA 세팅이 수백 줄.
> 공식 모듈은 그 모든 베스트 프랙티스를 *변수 몇 개* 로 가능하게 만든다 — 처음부터 본인이 짜지 마라.

### 3.3 IRSA (LB Controller 예시)

```hcl
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${module.eks.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
```

### 3.4 Helm 으로 Karpenter

```hcl
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.0.6"

  set {
    name  = "settings.clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter_irsa.iam_role_arn
  }

  depends_on = [module.eks]
}
```

> **🧠 "Helm 차트는 Terraform 으로 묶기 — but 손으로 차트 작성 X"**
> `helm_release` 로 *외부 공식 차트를 install* 하는 건 IaC 일관성에 좋다.
> 하지만 *Helm chart 자체를 Terraform 안에 쓰는 건* 두 도구의 abstraction 을 섞는 안티패턴 — 차트는 Helm 으로, install 만 Terraform 으로.

## 4. State 관리

학습용 — 로컬 state OK.
운영 — S3 backend + DynamoDB lock:
```hcl
terraform {
  backend "s3" {
    bucket         = "my-tf-state"
    key            = "eks/eks-study/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "tf-state-lock"
    encrypt        = true
  }
}
```

> **🧠 "tfstate 가 운영 인프라의 *유일한 진실 source*"**
> 로컬 tfstate 는 잃어버리면 끝 — *S3 backend + DynamoDB lock* 은 PoC 단계 지나면 즉시 도입.
> 특히 협업 환경에서 lock 없이는 *둘이 동시 apply* 로 state 깨질 수 있다.

## 5. 환경 분리 패턴

방법 1 — **workspace**:
```bash
terraform workspace new dev
terraform workspace select dev
terraform apply
```

방법 2 — **디렉토리**:
```
terraform/
├── modules/eks/         # 공통 모듈
├── envs/dev/main.tf     # dev 환경
└── envs/prod/main.tf
```

운영은 디렉토리 분리 권장 (state 분리 + IAM 분리 가능).

> **🧠 "workspace 는 *덫* — 운영 분리에는 부적합"**
> workspace 는 *같은 IAM/같은 backend* 를 공유 — 실수로 prod workspace 에 dev 변경 적용 가능.
> 진정한 환경 분리는 *디렉토리 + 별도 AWS account + 별도 state bucket* — 사고를 코드 구조로 막아라.

다음: [lab-01-cluster.md](./lab-01-cluster.md)
