# 03. 비용 가드레일

EKS는 학습 중 의외로 비용이 많이 나올 수 있습니다. 다음 원칙과 도구를 반드시 셋업하세요.

## 핵심 원칙 5가지

1. **실습 후 즉시 cleanup** — 모든 모듈 끝에 `cleanup.sh` 실행
2. **Spot 우선** — Karpenter 학습 단계부터 Spot 인스턴스 활용 (최대 70% 절감)
3. **NLB → ClusterIP 우선** — 학습용은 가능한 ClusterIP + `kubectl port-forward`
4. **NAT Gateway 비용 인식** — 시간당 약 0.045 USD + 데이터 전송. 안 쓸 때 삭제
5. **EBS gp3 사용** — gp2보다 저렴 + 빠름

## 주요 비용 항목 (`ap-northeast-2` 기준)

| 항목 | 단가 (대략) |
|------|------------|
| EKS Control Plane | $0.10/시간 (= 약 $73/월) |
| `t3.medium` On-Demand | $0.052/시간 |
| `t3.medium` Spot | $0.016/시간 (~70% 할인) |
| NAT Gateway | $0.045/시간 + $0.045/GB |
| Application Load Balancer | $0.0225/시간 + LCU |
| EBS gp3 100GB | $9.6/월 |

**10시간 학습 가정 (t3.medium 2대 + EKS + ALB):**
- EKS: 1.0 USD
- 노드 2대: 1.04 USD
- ALB: 0.225 USD
- **합계 약 2.3 USD**

## AWS Budgets 알람 설정

자동화 스크립트:

```bash
bash scripts/setup-budget-alarm.sh your-email@example.com 50
```

또는 콘솔에서:
1. AWS Console → Billing → Budgets → **Create budget**
2. 타입: Cost budget
3. 이름: `eks-study-budget`
4. 한도: 50 USD/월
5. 알람: 80% 도달 시 이메일

## 잔존 리소스 점검 명령

학습 종료 후 반드시 확인하세요:

### EC2 인스턴스
```bash
aws ec2 describe-instances \
  --query 'Reservations[].Instances[?State.Name==`running`].[InstanceId,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

### EKS 클러스터
```bash
aws eks list-clusters --output table
```

### Load Balancers
```bash
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]' --output table
aws elb describe-load-balancers \
  --query 'LoadBalancerDescriptions[].LoadBalancerName' --output table
```

### EBS Volumes (사용되지 않는 것)
```bash
aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size,CreateTime]' --output table
```

### EIP (사용되지 않는 것)
```bash
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' --output table
```

### NAT Gateway
```bash
aws ec2 describe-nat-gateways \
  --filter Name=state,Values=available \
  --query 'NatGateways[].[NatGatewayId,VpcId,CreateTime]' --output table
```

## 일괄 cleanup 패턴 (모듈별 예시)

각 모듈 `cleanup.sh`는 다음 순서를 따릅니다:

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. K8s 리소스 삭제 (Service of type LoadBalancer 먼저!)
kubectl delete -f manifests/ --ignore-not-found

# 2. ALB/NLB 정리 대기
sleep 30

# 3. (필요 시) 클러스터 삭제
# eksctl delete cluster --name eks-study --region ap-northeast-2
```

## 다음 단계

→ [04-ecr-setup.md](./04-ecr-setup.md)
