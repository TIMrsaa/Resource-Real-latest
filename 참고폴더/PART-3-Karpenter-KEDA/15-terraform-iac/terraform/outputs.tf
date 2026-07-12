# =============================================================================
# outputs.tf — Terraform 실행 결과로 노출할 값들
# =============================================================================
# Output이 왜 필요한가?
#   • apply 후 사용자에게 보여줄 정보 (kubeconfig 명령 등)
#   • 다른 Terraform stack에서 참조 (terraform_remote_state)
#   • CI/CD 파이프라인에서 사용 (terraform output -raw cluster_name)
#
# 사용:
#   terraform output                       # 모두 출력
#   terraform output cluster_endpoint      # 특정 값
#   terraform output -raw cluster_name     # 따옴표 없이 (스크립트용)
# =============================================================================

output "cluster_name" {
  value = module.eks.cluster_name
                                            # eks-study-tf
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
                                            # https://...eks.amazonaws.com
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
                                            # IRSA에 필요. 디버깅 시 확인용
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "kubeconfig_command" {
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
  description = "kubeconfig 등록 명령. apply 후 이 명령 복붙해서 실행하면 kubectl 사용 가능"
}

output "karpenter_iam_role_arn" {
  value = module.karpenter.iam_role_arn     # Karpenter Helm values에 사용된 ARN
}

output "lb_controller_iam_role_arn" {
  value = module.lb_controller_irsa.iam_role_arn
}

output "keda_iam_role_arn" {
  value = module.keda_irsa.iam_role_arn
}
