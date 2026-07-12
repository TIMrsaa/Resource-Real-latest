# Lab 02 — Prefix Delegation 적용과 밀도의 변화

> ⚠️ vpc-cni 설정 변경은 클러스터 전역 영향 — 공유 클러스터에서 다른 실습과 병행 중이면 타이밍 조율. 기존 노드는 설정 변경 후 **새로 뜨는 노드부터** 적용됩니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 현재 모드 확인

```bash
kubectl get ds aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env}' \
  | python3 -m json.tool | grep -A1 PREFIX
kubectl get node -o custom-columns='NAME:.metadata.name,PODS:.status.allocatable.pods'
```

## Step 2. 활성화 — 관리형 애드온 설정으로 (11의 방식 선행 체험)

```bash
aws eks update-addon --cluster-name $CLUSTER --region $AWS_REGION \
  --addon-name vpc-cni \
  --configuration-values '{"env":{"ENABLE_PREFIX_DELEGATION":"true","WARM_PREFIX_TARGET":"1"}}'
# 적용 대기
aws eks describe-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name vpc-cni \
  --query 'addon.status'
kubectl rollout status ds/aws-node -n kube-system
```

> kubectl set env로 직접 바꿀 수도 있지만 — 관리형 애드온 클러스터에선 **애드온 설정이 진실의 원천**(아니면 다음 애드온 업데이트가 원복시킵니다 — 11의 주제).

## Step 3. 새 노드로 효과 확인

기존 노드는 그대로입니다(부팅 시 결정) — 새 노드를 받아야 합니다:

```bash
# 노드그룹 desired+1 (또는 한 노드 교체)
NG=$(aws eks list-nodegroups --cluster-name $CLUSTER --region $AWS_REGION --query 'nodegroups[0]' --output text)
CUR=$(aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name $NG --region $AWS_REGION --query 'nodegroup.scalingConfig.desiredSize' --output text)
aws eks update-nodegroup-config --cluster-name $CLUSTER --nodegroup-name $NG --region $AWS_REGION \
  --scaling-config desiredSize=$((CUR+1))
kubectl get nodes -w    # 새 노드 합류 대기
```

```bash
# 새 노드의 allocatable.pods 비교!
kubectl get node -o custom-columns='NAME:.metadata.name,PODS:.status.allocatable.pods,AGE:.metadata.creationTimestamp'
```

예상: 새 노드의 PODS가 **110**(t3.medium 기준 상한) — 기존 17 대비 격변.

> eksctl 노드그룹이면 maxPods 자동 반영. 수동 구성이면 nodeadm으로 maxPods 상향(eks 05) 필요 — "프리픽스는 켰는데 maxPods 그대로"는 헛수고가 됩니다.

## Step 4. ENI에 프리픽스가 붙은 모습

```bash
NEWNODE=$(kubectl get nodes --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
NEWIID=$(aws ec2 describe-instances --region $AWS_REGION \
  --filters "Name=private-dns-name,Values=$NEWNODE" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ec2 describe-network-interfaces --region $AWS_REGION \
  --filters "Name=attachment.instance-id,Values=$NEWIID" \
  --query 'NetworkInterfaces[].{eni:NetworkInterfaceId,prefixes:Ipv4Prefixes[].Ipv4Prefix,ips:length(PrivateIpAddresses)}'
```

예상: `prefixes: ["10.0.x.0/28", ...]` — **낱장 secondary 대신 /28 묶음**이 붙어 있습니다.

✅ lab-01 Step 2와 비교하면 차이가 선명: 같은 ENI 슬롯으로 16배의 좌석. 서브넷 소비도 /28 단위라는 것 역시 확인(잔량이 16씩 줄어듭니다).

## Step 5. 조건의 함정 — 연속 블록 검증

```bash
# 서브넷 파편화 정도 감각 (가용 IP vs /28 가능성은 API로 직접 안 보임 — 실패 시 ipamd 로그에)
aws ec2 describe-subnets --region $AWS_REGION --subnet-ids \
  $(aws ec2 describe-instances --instance-ids $NEWIID --region $AWS_REGION --query 'Reservations[0].Instances[0].SubnetId' --output text) \
  --query 'Subnets[0].{cidr:CidrBlock,free:AvailableIpAddressCount}'
```

✅ 기억할 것: 오래 써서 IP가 파편화된 서브넷은 가용 수가 충분해 보여도 **연속 /28이 없어 프리픽스 할당 실패** 가능 — 증상은 ipamd 로그의 `InsufficientCidrBlocks`. 처방은 새 서브넷/보조 CIDR(16).

## Step 6. 운영 기준 기록 (산출물)

```markdown
# VPC CNI 설정 기준 (우리 클러스터)
- prefix delegation: ON (신규 표준) — 노드 교체로 점진 적용
- maxPods: eksctl 자동(110) / 수동 노드는 nodeadm으로
- warm: WARM_PREFIX_TARGET=1 (프리픽스 모드의 워밍)
- 알림: 서브넷 free IP < 20%, ipamd InsufficientCidrBlocks 로그
- 다음 단계(필요시): custom networking / IPv6 → 모듈 16
```

## 정리

```bash
bash cleanup.sh    # 노드 수 원복
```
