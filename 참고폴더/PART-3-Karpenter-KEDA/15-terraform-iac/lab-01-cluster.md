# Lab 01 — Terraform 으로 클러스터 만들기

> **🌱 핵심 개념 미리보기**
> - **Terraform state**: `terraform.tfstate` 파일에 모든 리소스 ID/속성 기록. 이게 진실의 원천.
> - **provider**: AWS/Helm/Kubernetes 등 외부 API 와 통신하는 플러그인. `init` 시 다운로드.
> - **module**: 재사용 가능한 리소스 묶음. `module.eks` 로 EKS 표준 셋업 캡슐화.
> - **target apply**: `-target=...` 로 특정 리소스만 우선 생성. 의존성 단계화에 유용.
> - **plan → apply**: plan 으로 변경 검토 후 apply. 운영 표준.

## 1. terraform 디렉토리 진입

```bash
cd terraform/
ls
```

기대:
```
versions.tf  variables.tf  locals.tf  outputs.tf
vpc.tf  eks.tf  irsa.tf
karpenter.tf  keda.tf  alb-controller.tf
```

## 2. terraform init

```bash
terraform init
```

→ `.terraform/` 안에 provider 와 모듈 다운로드. ~2분.

> **🧠 `terraform init` 가 하는 일**
> ① `required_providers` 블록 읽고 hashicorp/aws, hashicorp/helm 등을 다운로드 → `.terraform/providers/`.
> ② `module "..."` 의 source (예: `terraform-aws-modules/eks/aws`) 를 fetch.
> ③ backend (S3/local) 초기화 → tfstate 위치 결정.
> 처음 한 번만 무거우며, 이후엔 캐시 사용. 새 provider 추가 시 다시 호출 필요.

## 3. plan

```bash
terraform plan -out tf.plan
```

기대: 100+ 자원 생성 예정 (VPC, Subnet, IGW, NAT GW, EKS Cluster, NodeGroup, IAM Role, ...).

## 4. 자원 일부만 먼저 만들기 (학습 권장)

VPC + EKS 만 먼저 (Helm 은 나중에 — 의존성 명확화):
```bash
terraform apply -target=module.vpc -target=module.eks
```

소요: ~15분 (EKS 클러스터 자체 시간).

> **🧠 `-target` 의 트레이드오프**
> 의존성 단계화엔 좋지만 Terraform 공식은 비추 (warning 출력). state 와 실제 리소스의 부분 동기화 위험.
> 정상 흐름은 `terraform apply` 한 번이며, `-target` 은 "처음 셋업 / trouble shooting" 같은 예외용.
> 본 lab 에선 EKS 가 먼저 떠야 Helm 이 install 할 수 있어서 단계화가 합리적.

## 5. kubeconfig 등록

```bash
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

기대: 노드 2대 Ready.

## 6. 나머지 (Helm + Karpenter NodePool)

```bash
terraform apply
```

소요: 추가 5~7분.

> **🧠 Helm provider 의 갱신 동작**
> Terraform Helm provider 는 release 의 desired state 를 tfstate 에 저장. `values` 변경 시 helm upgrade 호출.
> chart 버전 핀 안 하면(latest) `terraform plan` 마다 drift 검출 가능 → 항상 버전 명시 권장.
> Helm 으로 만든 리소스(Pod, Service)는 tfstate 에 안 들어가지만, Karpenter NodePool 같은 CRD 는 `kubernetes_manifest` 로 별도 관리됨.

## 7. 확인

```bash
kubectl get nodepool,ec2nodeclass
kubectl get pods -n karpenter
kubectl get pods -n keda
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## 8. eksctl 로 만든 클러스터와 비교

| 항목 | eksctl | Terraform |
|------|--------|-----------|
| 클러스터 생성 시간 | 15~20분 | 동일 |
| Karpenter / KEDA 추가 명령 | 별도 helm install | 같은 apply 안에 |
| state 추적 | CFN | tfstate |
| 다음 변경 시 | clusterconfig 수정 + create-nodegroup 등 | terraform apply |
| 삭제 | eksctl delete (CFN 기반) | terraform destroy |

> **🧠 eksctl 과 Terraform 의 진짜 차이**
> eksctl = AWS 가 만든 EKS 전용 CLI. CFN(Cloud Formation) 으로 동작. 빠른 시작에 최적.
> Terraform = 범용 IaC. 멀티 클라우드, 외부 시스템 (Datadog/PagerDuty 등) 까지 한 state 로.
> 운영 환경은 보통 Terraform. 단, 학습/PoC 는 eksctl 이 압도적으로 빠름. 둘 다 알아두고 상황에 맞게.

다음: [lab-02-addons.md](./lab-02-addons.md)
