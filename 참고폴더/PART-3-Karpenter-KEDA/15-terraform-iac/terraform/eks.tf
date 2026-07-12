# =============================================================================
# eks.tf — EKS 클러스터 생성 (terraform-aws-modules/eks 모듈)
# =============================================================================
# 이 모듈이 만드는 것:
#   • EKS Control Plane
#   • 클러스터 IAM Role + 노드 IAM Role
#   • 클러스터 보안그룹
#   • OIDC Provider (IRSA용)
#   • Managed Node Group
#   • EKS Addon (vpc-cni, coredns 등)
#
# eksctl 과 비교:
#   • eksctl: YAML 1장으로 빠르게. 학습/PoC.
#   • Terraform: 변수화/모듈화 우수. 다른 AWS 리소스(SQS, RDS)와 통합.
#                정식 운영 권장.
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"   # 공식 EKS 모듈
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version       # K8s 1.35 (variables.tf 참고)

  # ── API 엔드포인트 접근 ──
  cluster_endpoint_public_access = true       # 인터넷에서 kubectl 접근 가능
                                              # 운영: 보통 false + private + 점프호스트
  enable_cluster_creator_admin_permissions = true
                                              # apply 한 사람이 cluster-admin 자동 부여
                                              # (kubectl 접근 즉시 가능)

  # ── VPC 연결 ──
  vpc_id     = module.vpc.vpc_id              # vpc.tf 에서 만든 VPC 참조
  subnet_ids = module.vpc.private_subnets     # 노드는 private에 (보안)

  # ── EKS Addon: AWS가 버전 관리해주는 부가 컴포넌트 ──
  cluster_addons = {
    vpc-cni = {                               # Pod에 VPC IP 직접 할당
      most_recent = true                      # 최신 버전 자동
    }
    coredns = {                               # 클러스터 내 DNS
      most_recent = true
    }
    kube-proxy = {                            # Service IP → Pod IP 라우팅
      most_recent = true
    }
    aws-ebs-csi-driver = {                    # PV 동적 프로비저닝
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
                                              # IRSA: SA에 IAM 매핑
    }
    eks-pod-identity-agent = {                # Pod Identity (IRSA 후속) 지원
      most_recent = true
    }
  }

  # ── Managed Node Group: AWS가 패치/업그레이드 관리 ──
  eks_managed_node_groups = {
    workers = {
      ami_type       = "AL2023_x86_64_STANDARD"   # AL2023 (Amazon Linux 2023)
      instance_types = ["t3.medium", "t3a.medium"] # AMD/Intel 섞기 (Spot 가용성 ↑)
      capacity_type  = "SPOT"                      # Spot (학습용 ~70% 할인)

      min_size     = 0                             # 0까지 줄일 수 있음
      max_size     = 6                             # 최대 6개
      desired_size = 2                             # 시작 2개

      labels = {                                   # K8s 노드 라벨
        workload-type = "general"
      }

      iam_role_additional_policies = {             # 노드 IAM Role에 추가 정책
        ECRReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
                                                   # ECR 이미지 pull 권한
      }
    }
  }

  # ── 노드 보안그룹에 Karpenter 발견용 태그 ──
  # Karpenter EC2NodeClass의 securityGroupSelectorTerms 가 이 태그로 검색
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}
