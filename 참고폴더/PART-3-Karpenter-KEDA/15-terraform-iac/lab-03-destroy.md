# Lab 03 — terraform destroy 로 정리

> **🌱 핵심 개념 미리보기**
> - **`terraform destroy`**: tfstate 의 모든 리소스를 역순(의존성 역방향)으로 삭제.
> - **K8s LB 우선 삭제**: ALB/NLB 는 K8s 가 만든 것 → Terraform 이 모름. 안 지우면 VPC 삭제 차단.
> - **잔존 리소스**: Karpenter 가 만든 EC2 / EBS 는 tfstate 밖 → 수동 확인 필요.
> - **tfstate 백업**: state 가 사라지면 어떤 리소스를 만들었는지 추적 불가 → 항상 보관.
> - **dry-run 없음**: destroy 는 plan 으로 검토 후 yes 입력. 한 번 실행되면 되돌릴 수 없음.

## 1. 사전 정리 — K8s 자원 먼저

LoadBalancer Service 는 직접 삭제. 안 그러면 ALB 가 남아 VPC 삭제 차단:
```bash
kubectl delete ingress --all -A
kubectl delete svc --field-selector spec.type=LoadBalancer -A
sleep 60
```

> **🧠 LB 가 VPC 삭제를 막는 이유**
> AWS LB Controller 가 ALB 를 만들면 ENI(Elastic Network Interface) 가 VPC 서브넷에 attach 됨.
> Terraform 이 VPC delete 시도 → 서브넷에 ENI 가 살아있어 `DependencyViolation` 에러 → destroy 영원히 stuck.
> Ingress/LB Service 를 K8s 에서 먼저 삭제 → controller 가 ALB+ENI 정리 → 60 초 대기 → VPC 삭제 가능.

## 2. terraform destroy

```bash
cd terraform/
terraform destroy
```

→ "Yes" 입력. 약 15분.

> **🧠 destroy 의 순서**
> Terraform 은 의존성 그래프의 역방향으로 삭제: NodePool → Helm release → EKS cluster → VPC.
> EKS cluster 삭제 시 NodeGroup 의 EC2 도 같이 사라짐 (cascade).
> Karpenter 가 만든 EC2 는 tfstate 에 없음 → cluster 삭제 시 "고아" 가 되고 결국 자체 종료 (kubelet 응답 없으면 AWS 가 정리), 하지만 안전상 수동 확인 권장.

## 3. 잔존 리소스 확인

```bash
echo "=== EKS Clusters ==="
aws eks list-clusters --region ap-northeast-2 | jq

echo "=== EC2 Instances (Karpenter / Node Group) ==="
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=eks-study-tf" \
  Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId'

echo "=== ALBs ==="
aws elbv2 describe-load-balancers --query 'LoadBalancers[?starts_with(LoadBalancerName,`k8s-`)].LoadBalancerName'

echo "=== EBS unattached ==="
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'

echo "=== VPC ==="
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=eks-study" --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0]]'
```

기대: 모두 비어있음. 무엇이 남으면 직접 삭제.

> **🧠 잘 빠뜨리는 잔존 리소스 5종**
> ① **Karpenter 가 만든 EC2** (tfstate 밖) ② **k8s-* 이름의 ALB/NLB** (LB Controller 산물) ③ **available 상태의 EBS** (PVC reclaim X) ④ **CloudWatch Log Group** (log retention 안 끝나면) ⑤ **ECR repository / IAM Role 잔여**.
> 한 곳만 남아도 시간당 $0.0X 누적 → 한 달 후 청구서 보고 깜짝 놀람. AWS Cost Anomaly Detection 활성화 권장.

## 4. tfstate 백업

```bash
mv terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)
ls -la *.tfstate*
```

state 는 학습 기록으로 보관 권장.

> **🧠 운영 환경에선 tfstate 어디 두나**
> 로컬 tfstate 는 학습용. 운영 표준은 **S3 backend + DynamoDB lock**:
> ```
> backend "s3" { bucket = "tf-state-prod" key = "eks/terraform.tfstate" dynamodb_table = "tf-lock" }
> ```
> S3 = 영속성/버전관리, DynamoDB = 동시 apply 방지 락. team 협업 필수 인프라. 학습 후 다음 단계로 권장.

## Part 3 종료

축하합니다 🎉 — Part 3 완료.

남은 것: Part 4 운영/트러블슈팅.

- 만약 Part 4 진행 전 잠시 쉬려면, 클러스터를 삭제했으니 비용 0.
- Part 4 시작 시 클러스터 다시 생성:

```bash
# Option A: eksctl
eksctl create cluster -f ../../PART-2-EKS-Practice/05-eks-cluster-eksctl/manifests/cluster.yaml

# Option B: terraform
cd terraform/ && terraform apply
```

다음: [quiz.md](./quiz.md)
