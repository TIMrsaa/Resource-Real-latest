# =============================================================================
# keda.tf — KEDA 설치 (Helm)
# =============================================================================
# KEDA = Kubernetes Event-Driven Autoscaling
# 60+ 트리거(SQS, Kafka, Prometheus 등) 기반 Pod 자동 스케일링
#
# IRSA 활성화:
#   KEDA Operator가 SQS API 호출하려면 IAM 권한 필요
#   irsa.tf의 keda_irsa 모듈로 만든 Role을 SA에 매핑
# =============================================================================

resource "helm_release" "keda" {
  namespace        = "keda"
  create_namespace = true                  # NS 자동 생성
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  version          = "2.15.1"              # 차트 버전 고정

  # IRSA 활성화 (KEDA Operator의 SA에 IAM Role 매핑)
  set {
    name  = "podIdentity.aws.irsa.enabled"
    value = "true"
  }
  # SA에 부착할 IAM Role ARN (어노테이션으로)
  # \\. 이스케이프: Helm set 문법에서 점(.)은 경로 구분자라 escape 필요
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.keda_irsa.iam_role_arn
  }

  depends_on = [module.eks]                # EKS 먼저 만들어진 후
}
