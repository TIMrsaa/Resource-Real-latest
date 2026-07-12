# =============================================================================
# variables.tf — Terraform 변수 정의 (입력값)
# =============================================================================
# 변수 우선순위 (높은 순):
#   1) -var "key=value" CLI 옵션
#   2) -var-file="prod.tfvars" CLI 옵션
#   3) terraform.tfvars 파일 (자동 로드)
#   4) *.auto.tfvars 파일들
#   5) TF_VAR_<name> 환경변수
#   6) default 값 (이 파일)
#
# 사용 예:
#   terraform apply                            # default 값 사용
#   terraform apply -var "cluster_name=prod"   # 덮어쓰기
#   terraform apply -var-file=prod.tfvars      # 파일로 덮어쓰기
# =============================================================================

variable "cluster_name" {
  type        = string                # 변수 타입 (string/number/bool/list/map/object)
  default     = "eks-study-tf"        # 기본값
  description = "EKS 클러스터 이름. AWS 콘솔/CLI에서 식별자로 사용"
}

variable "cluster_version" {
  type        = string
  default     = "1.35"
  description = "Kubernetes 버전. EKS 지원 버전 확인 필수 (2026-05 기준 표준 지원: 1.30~1.35)"
}

variable "region" {
  type        = string
  default     = "ap-northeast-2"      # 서울
  description = "AWS 리전. 변경 시 AZ도 자동으로 따라감 (locals.tf)"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.30.0.0/16"        # 65,536개 IP. 다른 VPC와 겹치지 않게
  description = "VPC IP 대역. /16 권장 (충분한 IP 확보)"
}

variable "tags" {
  type = map(string)                  # 키-값 맵
  default = {
    Project     = "eks-study"         # 비용 추적 (Cost Explorer 필터)
    ManagedBy   = "terraform"         # 누가 관리? (수작업/Terraform/eksctl)
    Environment = "learning"          # 환경 (dev/staging/prod/learning)
  }
  description = "모든 AWS 리소스에 부착될 태그. 비용/소유권 추적용"
}
