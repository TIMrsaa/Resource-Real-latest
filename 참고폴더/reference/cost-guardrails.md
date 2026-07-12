# 비용 가드레일

## 핵심 원칙 (반드시 지킬 것)

### 1. 학습 후 즉시 cleanup
모든 모듈은 `cleanup.sh`로 마무리. 가장 흔한 비용 사고:
- EKS 클러스터 그대로 둠 → 매시간 $0.10
- LoadBalancer Service 가 ALB/NLB를 만들어 둠 → 시간당 $0.0225+
- 사용하지 않는 EBS gp3 100GB → 월 $9.6
- 미사용 EIP → 시간당 $0.005
- 미사용 NAT Gateway → 시간당 $0.045

### 2. Spot 우선 (Karpenter)
On-Demand 대비 약 70% 절감. 학습 환경에서는 가용성보다 비용이 우선.

```yaml
# Karpenter NodePool 예시
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
```

### 3. ClusterIP + port-forward
LoadBalancer 대신 학습 시에는:
```bash
kubectl port-forward svc/my-svc 8080:80
```

### 4. EBS gp3 사용
gp2 대비 저렴 + 빠름. StorageClass 기본값으로 지정.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
volumeBindingMode: WaitForFirstConsumer
```

### 5. AWS Budgets 알람
50 USD 예산, 80% 도달 시 이메일.

```bash
bash 00-prerequisites/scripts/setup-budget-alarm.sh your@email.com 50
```

## 비용 모니터링 명령

```bash
# 최근 7일 일별 비용
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-7d +%F),End=$(date -u +%F) \
  --granularity DAILY --metrics UnblendedCost \
  --query 'ResultsByTime[*].[TimePeriod.Start,Total.UnblendedCost.Amount]' \
  --output table

# 서비스별 누적
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-30d +%F),End=$(date -u +%F) \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output table
```

## 잔존 리소스 점검 스크립트

학습 종료 후 매번 실행:

```bash
#!/usr/bin/env bash
echo "=== Running EC2 ==="
aws ec2 describe-instances \
  --query 'Reservations[].Instances[?State.Name==`running`].[InstanceId,InstanceType]' \
  --output text

echo "=== EKS Clusters ==="
aws eks list-clusters --output text

echo "=== Load Balancers ==="
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text
aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text

echo "=== Unattached EBS volumes ==="
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size]' --output table

echo "=== Idle Elastic IPs ==="
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' --output table

echo "=== NAT Gateways ==="
aws ec2 describe-nat-gateways --filter Name=state,Values=available \
  --query 'NatGateways[].[NatGatewayId,VpcId]' --output table
```

## 모듈별 예상 비용 (참고)

| 파트 | 모듈 수 | 예상 비용 (학습 끝나면 cleanup 가정) |
|------|---------|--------------------------------------|
| 00-prerequisites | 1 | 0 USD |
| Part 1 | 4 | 5 ~ 10 USD (최소 EKS만 사용) |
| Part 2 | 5 | 20 ~ 30 USD (EKS + ALB + EBS) |
| Part 3 | 6 | 30 ~ 50 USD (Karpenter 부하 테스트, Spot 사용) |
| Part 4 | 3 | 10 ~ 20 USD (트러블슈팅 시뮬레이션) |
| **합계** | 18 | **65 ~ 110 USD** |

> 학습 페이스에 따라 변동. 매일 실습 후 cleanup하면 이 범위 안에서 유지 가능.
