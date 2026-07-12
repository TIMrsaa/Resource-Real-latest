# Lab 02 — 비용 해부와 절감 지도

> "EKS가 비싸요"의 8할은 EKS가 아니라 **주변 리소스**입니다. 내 학습 클러스터의 실제 비용원을 전부 찾아내고, 휴지기 절차를 만듭니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 비용원 전수 조사 — 내 클러스터에 딸린 것들

```bash
# ① 노드 (최대 비용원)
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=$CLUSTER" \
  "Name=instance-state-name,Values=running" --region $AWS_REGION \
  --query 'Reservations[].Instances[].{type:InstanceType,az:Placement.AvailabilityZone}' --output table

# ② 로드밸런서 (Ingress/Service가 만든 것 — k8s 05/06에서!)
aws elbv2 describe-load-balancers --region $AWS_REGION \
  --query 'LoadBalancers[].{name:LoadBalancerName,type:Type,created:CreatedTime}' --output table

# ③ EBS 볼륨 (PVC 잔존물 — k8s 19 pitfall의 실물 확인)
aws ec2 describe-volumes --region $AWS_REGION \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
  --query 'Volumes[].{id:VolumeId,size:Size,state:State}' --output table

# ④ NAT Gateway (프라이빗 서브넷이 있으면)
aws ec2 describe-nat-gateways --region $AWS_REGION \
  --filter "Name=state,Values=available" --query 'NatGateways[].{id:NatGatewayId,subnet:SubnetId}' --output table

# ⑤ EIP, 스냅샷 (모듈 36의 잔존물 가능성)
aws ec2 describe-addresses --region $AWS_REGION --query 'Addresses[?AssociationId==null].PublicIp'
aws ec2 describe-snapshots --owner-ids self --region $AWS_REGION --query 'length(Snapshots)'
```

✅ **발견된 것을 표로**: 예상 못 한 LB나 `available` 상태(어디에도 안 붙은) EBS가 나오면 — 그게 "새는 돈"입니다. k8s 파트 cleanup을 빼먹은 모듈이 있다는 뜻이기도 (해당 cleanup.sh 재실행).

## Step 2. 월 비용 추정 워크시트

```markdown
# k8s-study 월 비용 추정 (ap-northeast-2, 24시간 가동 기준)
| 항목 | 수량 | 단가(시간) | 월(≈730h) |
|------|------|-----------|----------|
| EKS control plane | 1 | $0.10 | $73 |
| 노드 t3.medium×2 (예) | 2 | ~$0.052×2 | ~$76 |
| ALB (있다면) | 1 | ~$0.0225+LCU | ~$20+ |
| NAT GW (있다면) | 1 | ~$0.059+GB | ~$43+ |
| EBS gp3 (잔존 GB) | __GB | $0.08/GB·월 | $__ |
| 합계 | | | **$200± ← 방치 시** |
```

(단가는 변합니다 — 정확한 값은 요금 페이지에서. 핵심은 **구조**: 고정비가 노드+CP+NAT 세 덩어리)

## Step 3. 휴지기 절차 만들기 — 노드를 0으로

control plane($73/월)만 남기고 다 끄는 법:

```bash
# 노드그룹 0으로 (클러스터/설정은 보존 — 재개 시 다시 늘리면 끝)
NG=$(aws eks list-nodegroups --cluster-name $CLUSTER --region $AWS_REGION --query 'nodegroups[0]' --output text)
aws eks update-nodegroup-config --cluster-name $CLUSTER --nodegroup-name $NG \
  --scaling-config minSize=0,maxSize=3,desiredSize=0 --region $AWS_REGION
# 확인 (수 분 후)
kubectl get nodes    # No resources found
```

재개:
```bash
aws eks update-nodegroup-config --cluster-name $CLUSTER --nodegroup-name $NG \
  --scaling-config minSize=0,maxSize=3,desiredSize=2 --region $AWS_REGION
```

✅ 주의 두 가지: ① Pod들은 노드와 함께 사라집니다(상태는 PVC/외부 저장소에 — k8s 08/19의 원칙이 여기서 보상) ② LB/NAT/EBS는 노드와 무관하게 계속 과금 — **Step 1의 목록이 진짜 끄기 체크리스트**입니다. 장기 휴지면 클러스터 삭제 + 재생성 스크립트(eksctl 설정 파일 — 모듈 02)가 정답.

## Step 4. 태그 — 비용 추적의 씨앗 (모듈 22 예고)

```bash
aws eks tag-resource --resource-arn \
  $(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.arn' --output text) \
  --tags project=k8s-study,owner=$(whoami),purpose=learning
```

✅ Cost Explorer에서 태그별 필터가 가능해집니다 — "이 클러스터에 든 총 비용"을 묻는 날(모듈 22)을 위한 한 줄.

## Step 5. 산출물 — 나의 비용 운영 수칙

```markdown
# 비용 수칙 (학습 기간)
1. 세션 종료마다: 모듈 cleanup.sh 실행 (특히 LB/PVC 만든 모듈)
2. 휴지기(3일+): 노드 desiredSize=0 / 장기(2주+): 클러스터 삭제
3. 주 1회: Step 1 전수 조사 명령 5종 실행 — "예상 밖 리소스" 사냥
4. 절대 금지: 연장 지원(EXTENDED) 진입 — 업그레이드 달력에 알림
```
