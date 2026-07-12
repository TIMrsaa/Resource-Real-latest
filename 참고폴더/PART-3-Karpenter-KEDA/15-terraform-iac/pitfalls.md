# 흔한 함정 5선 — 15. Terraform IaC

## 1. `kubernetes_manifest` 가 Karpenter Helm 보다 먼저 적용되어 실패

**증상**: NodePool/EC2NodeClass 의 CRD 를 못 찾음.

**원인**: Helm 으로 Karpenter 가 떠야 CRD 가 등록됨. 의존성 누락.

**해결**: `time_sleep` 또는 `depends_on`:
```hcl
resource "time_sleep" "wait_karpenter" {
  depends_on      = [helm_release.karpenter]
  create_duration = "30s"
}

resource "kubernetes_manifest" "default_nodepool" {
  ...
  depends_on = [time_sleep.wait_karpenter]
}
```

또는 NodePool/EC2NodeClass 는 별도 stage 로 (분리된 terraform 코드).

---

## 2. terraform destroy 가 VPC 삭제에서 멈춤

**증상**: `Error: dependency violation: ... has dependencies and cannot be deleted`.

**원인**: K8s LoadBalancer Service 가 만든 ALB/NLB 가 남아 ENI 점유 → VPC subnet 삭제 차단.

**해결**:
```bash
kubectl delete svc --field-selector spec.type=LoadBalancer -A
kubectl delete ingress -A
sleep 60
terraform destroy
```

---

## 3. tfstate 충돌 (협업 시)

**증상**: 두 명이 동시에 apply 하면 state 가 꼬임.

**원인**: 로컬 tfstate 사용.

**해결**: S3 backend + DynamoDB lock:
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

---

## 4. Helm chart 버전을 안 고정해 reproducibility 깨짐

**증상**: 같은 코드를 다음 달에 apply 하니 다른 동작.

**원인**: `helm_release` 의 `version` 필드 누락 → latest 사용 → 차트 발전.

**해결**: 모든 `helm_release` 에 `version` 명시:
```hcl
resource "helm_release" "karpenter" {
  ...
  version = "1.0.6"     # 명시적으로
}
```

운영은 chart version 도 git 추적 가능한 형태로.

---

## 5. EKS Managed Node Group 의 자동 업데이트가 깜짝 disruption

**증상**: 어느 날 자동으로 노드 회전이 일어나 Pod 재시작.

**원인**: `module.eks.cluster_addons.vpc-cni.most_recent = true` 같은 설정 → 새 버전 자동 채택. 노드 그룹의 launch template 도 자동 업데이트 가능.

**해결**:
- 명시적 버전 핀:
```hcl
cluster_addons = {
  vpc-cni = { addon_version = "v1.18.0-eksbuild.1" }
}
```
- 노드 그룹의 launch template 명시
- 업그레이드는 의도적으로 (PR 리뷰 후 apply)
