# =============================================================================
# versions.tf — Terraform 버전 + Provider 정의 + 인증 설정
# =============================================================================
# Provider란?
#   특정 클라우드/서비스의 API를 Terraform 리소스로 매핑하는 플러그인
#   AWS, Azure, GCP, K8s, Helm 등 수천 개의 provider 존재
#
# 이 파일이 하는 일:
#   1) Terraform 자체 버전 요구사항 (>= 1.7)
#   2) 사용할 provider와 버전 (aws, helm, kubernetes)
#   3) 각 provider의 인증/연결 설정
#
# 핵심 디자인 패턴:
#   K8s/Helm provider가 EKS API를 호출하려면 토큰이 필요
#   → exec 블록으로 'aws eks get-token' 호출해 토큰 동적 획득
#   → 클러스터 자격 증명을 파일에 저장 안 해도 됨 (보안)
# =============================================================================

terraform {
  required_version = ">= 1.7"        # Terraform CLI 최소 버전 (1.7+ 기능 사용)

  required_providers {
    aws = {
      source  = "hashicorp/aws"      # registry.terraform.io/hashicorp/aws
      version = "~> 5.50"            # ~> 5.50 = 5.50.x 만 (마이너 픽스 허용, 메이저 X)
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

# ── AWS Provider: 모든 AWS API 호출의 기본 ────────────────────
# 자격증명 출처 (자동 탐색 순서):
#   1) AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY 환경변수
#   2) ~/.aws/credentials 의 default 프로파일
#   3) IAM Role (EC2/ECS/Lambda 인스턴스 메타데이터)
provider "aws" {
  region = var.region                # ap-northeast-2 (서울)
}

# ── Kubernetes Provider: K8s API 직접 호출용 ──────────────────
# K8s 객체(SA, ConfigMap 등)를 Terraform 리소스로 만들 때 필요
provider "kubernetes" {
  # EKS API 서버 엔드포인트 (https://...eks.amazonaws.com)
  host = module.eks.cluster_endpoint

  # 클러스터 CA 인증서 (base64 인코딩 → 디코딩 필요)
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  # ★ 핵심: AWS CLI를 호출해 동적으로 토큰 획득
  # = "aws eks get-token --cluster-name eks-study-tf" 실행 결과 사용
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

# ── Helm Provider: Helm 차트 설치/관리용 ──────────────────────
# Karpenter, KEDA, ALB Controller 등을 Helm으로 설치
provider "helm" {
  # kubernetes provider와 동일한 인증 (중복 작성 필요)
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}
