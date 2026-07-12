# =============================================================================
# irsa.tf — IRSA (IAM Role for Service Accounts) 설정 모음
# =============================================================================
# IRSA란?
#   K8s ServiceAccount 에 AWS IAM Role 을 매핑하는 EKS 기능.
#   Pod가 AWS API 호출 시 노드 IAM 이 아닌 자기 SA의 IAM 으로 동작.
#
# 왜 필요한가? (보안)
#   노드 IAM에 모든 권한 = 그 노드의 모든 Pod에게 권한 부여 (위험!)
#   IRSA = Pod 단위 최소 권한 (Principle of Least Privilege)
#
# 동작 원리:
#   1) EKS의 OIDC Provider를 IAM에 등록
#   2) IAM Role의 Trust Policy: "이 OIDC + 특정 SA만 이 Role 빌릴 수 있음"
#   3) SA에 어노테이션: eks.amazonaws.com/role-arn=arn:aws:iam::...
#   4) Pod이 SA로 토큰 요청 → AWS STS가 임시 자격증명 발급
#
# 이 파일에서 만드는 IRSA 4개:
#   • EBS CSI: PV 만들 때 EBS 생성 권한
#   • LB Controller: ALB 만들 권한
#   • Karpenter: EC2 생성/SQS 권한 + 노드 IAM Role
#   • KEDA: SQS 큐 길이 조회 권한
# =============================================================================

# ── 1. EBS CSI Driver IRSA ───────────────────────────────────────
# kube-system/ebs-csi-controller-sa 가 EBS API 호출 시 사용
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true              # 모듈이 미리 정의해둔 정책 자동 부착

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
                                            # 이 SA만 Role 빌릴 수 있음
    }
  }

  tags = var.tags
}

# ── 2. AWS Load Balancer Controller IRSA ─────────────────────────
# kube-system/aws-load-balancer-controller 가 ALB API 호출 시 사용
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true   # ALB 관련 정책 일괄 부착

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

# ── 3. Karpenter (전용 헬퍼 모듈 사용) ───────────────────────────
# 이 모듈이 한번에 만드는 것:
#   • Karpenter 컨트롤러 IAM Role (EC2 생성/관리 권한)
#   • Karpenter 노드 IAM Role (Pod 실행, ECR pull 등)
#   • Spot 회수 알림용 SQS 큐 + EventBridge Rule
#   • 노드 IAM Instance Profile
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  # Pod Identity (EKS 신기술) vs IRSA (구기술)
  # 학습용으로 IRSA 사용 (자료가 더 많음)
  enable_pod_identity             = false
  create_pod_identity_association = false
  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]
                                            # karpenter NS의 karpenter SA

  # 노드 IAM Role에 추가 정책 부착 (기본 EKS 노드 정책 외에)
  node_iam_role_additional_policies = {
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
                                              # ECR 이미지 pull
    AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
                                              # SSM Session Manager 접속용 (디버깅)
  }

  tags = var.tags
}

# ── 4. KEDA Operator IRSA (SQS 큐 길이 조회용) ───────────────────
module "keda_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-keda"
  role_policy_arns = {
    sqs = "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"
                                            # SQS 읽기만 (큐 길이 조회용)
                                            # 메시지 수신/삭제는 Pod의 별도 SA로
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["keda:keda-operator"]
    }
  }

  tags = var.tags
}
