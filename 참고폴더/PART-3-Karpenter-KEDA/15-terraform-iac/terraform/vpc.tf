# =============================================================================
# vpc.tf — EKS용 VPC 생성 (terraform-aws-modules/vpc 모듈 사용)
# =============================================================================
# 모듈이 만들어주는 것:
#   • VPC + 인터넷 게이트웨이
#   • Public 서브넷 3개 (AZ별 1개) — ALB, NAT용
#   • Private 서브넷 3개 (AZ별 1개) — EKS 노드, Pod IP
#   • NAT Gateway (private → 인터넷)
#   • 라우팅 테이블 + 연결
#
# 왜 Public/Private 분리?
#   • Public  : 외부 접근 필요한 것 (ALB, NAT)
#   • Private : 노드, DB 등 (외부에서 직접 접근 X = 보안)
#   Pod이 인터넷 호출 시: Pod → Private subnet → NAT → 인터넷
#
# IP 대역 분할 (cidrsubnet):
#   var.vpc_cidr = 10.30.0.0/16 (65,536 IP)
#   cidrsubnet(/16, 8, 1)   = 10.30.1.0/24   (256 IP, private a)
#   cidrsubnet(/16, 8, 2)   = 10.30.2.0/24   (256 IP, private b)
#   cidrsubnet(/16, 8, 3)   = 10.30.3.0/24   (256 IP, private c)
#   cidrsubnet(/16, 8, 101) = 10.30.101.0/24 (256 IP, public a)
#   ...
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"   # 공식 AWS VPC 모듈
  version = "~> 5.0"

  name = var.cluster_name              # VPC 이름
  cidr = var.vpc_cidr                  # 10.30.0.0/16

  azs = local.azs                      # ["ap-northeast-2a", "2b", "2c"]

  # ── 서브넷 자동 분할 (cidrsubnet 함수) ──
  # cidrsubnet(prefix, newbits, netnum)
  #   prefix : 부모 CIDR
  #   newbits: 추가 prefix 비트 수 (8 → /24 생성)
  #   netnum : 몇 번째 서브넷
  private_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 1),    # 10.30.1.0/24
    cidrsubnet(var.vpc_cidr, 8, 2),    # 10.30.2.0/24
    cidrsubnet(var.vpc_cidr, 8, 3),    # 10.30.3.0/24
  ]
  public_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 101),  # 10.30.101.0/24
    cidrsubnet(var.vpc_cidr, 8, 102),
    cidrsubnet(var.vpc_cidr, 8, 103),
  ]

  enable_nat_gateway   = true          # NAT GW 생성 (private→인터넷)
  single_nat_gateway   = true          # 1개만 (학습 비용 ↓)
                                       # false = AZ별 1개 (HA + 비용 ↑)
  enable_dns_hostnames = true          # EC2에 *.compute.amazonaws.com DNS 부여 (필수)

  # ── ELB 발견용 태그 (AWS Load Balancer Controller용) ──
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"     # 외부 ALB가 이 서브넷에 생성됨
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"           # 내부 ALB
    "karpenter.sh/discovery"          = var.cluster_name  # ← Karpenter가 이 태그로 서브넷 검색
  }

  tags = var.tags                      # 모든 리소스에 공통 태그
}
