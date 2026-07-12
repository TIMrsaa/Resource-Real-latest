# =============================================================================
# alb-controller.tf — AWS Load Balancer Controller 설치
# =============================================================================
# 이 컨트롤러가 하는 일:
#   • Ingress 리소스 감지 → AWS ALB 자동 프로비저닝
#   • Service type=LoadBalancer (NLB 필요시) 도 처리
#
# 설치 순서:
#   1) IRSA용 ServiceAccount 생성 (어노테이션으로 IAM Role ARN 부착)
#   2) Helm으로 컨트롤러 설치 (위 SA를 사용하도록 지시)
#
# 왜 SA를 Terraform으로 따로 만드는가?
#   Helm 차트의 SA는 IRSA 어노테이션을 set으로 주입하기 까다로움
#   → SA를 먼저 만들고, Helm은 "create=false, name=existing" 으로 사용
# =============================================================================

# ── 1. IRSA용 ServiceAccount 생성 ────────────────────────────────
resource "kubernetes_service_account" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"               # 표준 위치
    annotations = {
      # IRSA 매핑: 이 SA로 Pod 뜨면 이 IAM Role 빌림
      "eks.amazonaws.com/role-arn" = module.lb_controller_irsa.iam_role_arn
    }
  }
}

# ── 2. Helm으로 LB Controller 설치 ──────────────────────────────
resource "helm_release" "aws_lb_controller" {
  namespace  = "kube-system"
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name         # 어떤 EKS 클러스터에서 동작?
  }
  set {
    name  = "serviceAccount.create"
    value = "false"                         # 차트가 SA 만들지 않음 (위에서 만든 거 사용)
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lb_controller.metadata[0].name
                                            # 위에서 만든 SA 이름 참조
  }
  set {
    name  = "region"
    value = var.region                      # API 호출 리전
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id               # ALB가 만들어질 VPC
  }

  depends_on = [kubernetes_service_account.lb_controller]
                                            # SA 먼저 생성 후 Helm install
}
