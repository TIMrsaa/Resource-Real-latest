# =============================================================================
# karpenter.tf — Karpenter 설치 + 기본 NodePool/EC2NodeClass 생성
# =============================================================================
# 단계:
#   1) Helm으로 Karpenter 컨트롤러 설치 (helm_release.karpenter)
#   2) 30초 대기 (CRD 등록 시간 확보) (time_sleep)
#   3) 기본 NodePool + EC2NodeClass 적용 (kubernetes_manifest)
#
# 왜 time_sleep이 필요한가?
#   Helm으로 Karpenter 설치 = NodePool/EC2NodeClass CRD가 K8s에 등록됨
#   하지만 등록 후 즉시 사용하면 "kind not found" 에러 발생 가능
#   → 30초 sleep으로 안전하게 (운영도 흔히 사용하는 패턴)
# =============================================================================

# ── 1. Karpenter 컨트롤러 설치 (Helm) ────────────────────────────
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true                # NS 자동 생성
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"   # AWS ECR Public (OCI 레지스트리)
  chart            = "karpenter"
  version          = "1.0.6"             # 차트 버전 고정 (재현성)

  values = [
    # yamlencode = HCL 객체를 YAML 문자열로 변환
    # Helm values를 인라인으로 정의 (별도 yaml 파일 안 만들어도 됨)
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        interruptionQueue = module.karpenter.queue_name   # Spot 회수 알림 SQS
                                                           # (irsa.tf의 karpenter 모듈이 만듦)
      }
      serviceAccount = {
        annotations = {
          # IRSA: Karpenter SA에 IAM Role 매핑 (EC2 생성 권한)
          "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
        }
      }
      controller = {
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { memory = "1Gi" }
        }
      }
    })
  ]

  depends_on = [module.eks, module.karpenter]   # EKS + IAM 먼저 만들어진 후
}

# ── 2. CRD 등록 대기 ─────────────────────────────────────────────
resource "time_sleep" "wait_karpenter" {
  depends_on      = [helm_release.karpenter]
  create_duration = "30s"                # 30초 대기
}

# ── 3. 기본 NodePool 생성 ────────────────────────────────────────
# kubernetes_manifest = 임의의 K8s 리소스를 YAML로 적용
# (Karpenter CRD 같이 Terraform이 직접 모르는 타입도 처리)
resource "kubernetes_manifest" "default_nodepool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        metadata = {
          labels = { managed-by = "karpenter" }   # Pod nodeSelector용
        }
        spec = {
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot"] },
            { key = "karpenter.k8s.aws/instance-cpu", operator = "In", values = ["2", "4", "8"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["2"] }
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"                    # 아래에서 만드는 EC2NodeClass 참조
          }
          expireAfter = "168h"                   # 7일 후 노드 자동 교체 (보안 패치)
        }
      }
      limits = { cpu = "100" }                   # 100 vCPU 한도 (비용 안전장치)
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s"
      }
    }
  }
  depends_on = [time_sleep.wait_karpenter]
}

# ── 4. 기본 EC2NodeClass 생성 (AWS EC2 설정) ────────────────────
resource "kubernetes_manifest" "default_ec2nodeclass" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      amiFamily = "AL2023"
      amiSelectorTerms = [
        { alias = "al2023@latest" }              # 최신 AL2023 AMI
      ]
      role = module.karpenter.node_iam_role_name # 노드 IAM (irsa.tf 의 karpenter 모듈)
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
                                                  # vpc.tf의 private_subnet_tags 와 매칭
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
                                                  # eks.tf의 node_security_group_tags 와 매칭
      ]
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize = "30Gi"
            volumeType = "gp3"
            encrypted  = true
          }
        }
      ]
      tags = var.tags                            # 생성되는 EC2에 부착될 태그
    }
  }
  depends_on = [time_sleep.wait_karpenter]
}
