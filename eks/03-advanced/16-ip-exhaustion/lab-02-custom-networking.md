# Lab 02 — 영토 확장: secondary CIDR로 Pod 이주시키기

theory §4의 다섯 부품을 순서대로 조립합니다. 목표 장면: **노드는 10.x에 사는데, 그 위의 Pod는 100.64.x에 사는** 것을 눈으로 확인하기.

> ⚠️ 클러스터 전역 설정(aws-node env)을 켭니다. 새 노드에만 적용되므로 기존 워크로드는 무사하지만, **끝나면 반드시 cleanup.sh로 원복** — 이 약속이 이 랩의 입장권입니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
VPC=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
```

## Step 1. 부품 ① — VPC에 두 번째 대역 연결

```bash
aws ec2 associate-vpc-cidr-block --vpc-id $VPC --cidr-block 100.64.0.0/16 --region $AWS_REGION
aws ec2 describe-vpcs --vpc-ids $VPC --region $AWS_REGION \
  --query 'Vpcs[0].CidrBlockAssociationSet[].{cidr:CidrBlock,state:CidrBlockState.State}' --output table
```

예상: 10.x(기존) + 100.64.0.0/16(associated). VPC는 여러 대역을 가질 수 있습니다 — Pod의 신도시 부지 확보.

## Step 2. 부품 ② — AZ별 Pod 전용 서브넷

```bash
AZS=($(aws ec2 describe-subnets --region $AWS_REGION \
  --filters Name=vpc-id,Values=$VPC --query 'Subnets[].AvailabilityZone' --output text | tr '\t' '\n' | sort -u))
declare -A PODNET
CIDRS=(100.64.0.0/19 100.64.32.0/19 100.64.64.0/19)
for i in "${!AZS[@]}"; do
  [ $i -ge 3 ] && break
  PODNET[${AZS[$i]}]=$(aws ec2 create-subnet --vpc-id $VPC --region $AWS_REGION \
    --availability-zone ${AZS[$i]} --cidr-block ${CIDRS[$i]} \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=podnet-iplab}]' \
    --query 'Subnet.SubnetId' --output text)
  echo "${AZS[$i]} → ${PODNET[${AZS[$i]}]}"
done
```

/19 하나 = 약 8,000 IP — Pod 예산이 자릿수부터 달라집니다. (라우팅은 VPC 로컬 통신이면 main 라우트 테이블로 충분 — NAT 경유 egress가 필요한 프로덕션 설계는 라우트 연결까지)

## Step 3. 부품 ③ — ENIConfig: "이 AZ의 Pod ENI는 이 서브넷으로"

```bash
# 클러스터 SG (Pod ENI에 붙일 것)
SG=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

for az in "${!PODNET[@]}"; do
cat <<EOF | kubectl apply -f -
apiVersion: crd.k8s.amazonaws.com/v1alpha1
kind: ENIConfig
metadata: { name: $az }          # ★ 이름 = AZ명 — 라벨 매칭의 열쇠
spec:
  subnet: ${PODNET[$az]}
  securityGroups: [$SG]
EOF
done
kubectl get eniconfig
```

## Step 4. 부품 ④ — CNI에 새 규칙 통보 (전역 스위치)

```bash
kubectl set env ds aws-node -n kube-system \
  AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true \
  ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone
kubectl rollout status ds/aws-node -n kube-system
```

`ENI_CONFIG_LABEL_DEF=zone 라벨`: 노드가 자기 AZ 라벨과 **같은 이름의 ENIConfig**를 자동으로 찾습니다 — Step 3에서 이름을 AZ로 지은 이유.

## Step 5. 부품 ⑤ — 새 노드 (기존 노드는 문법이 안 바뀝니다)

```bash
eksctl create nodegroup --cluster $CLUSTER --region $AWS_REGION \
  --name ip-lab --nodes 1 --node-type t3.medium \
  --node-labels iplab=true
kubectl get nodes -l iplab=true    # Ready 대기
```

## Step 6. 결정적 장면 — 두 대륙의 주소

```bash
NEW_NODE=$(kubectl get nodes -l iplab=true -o jsonpath='{.items[0].metadata.name}')

# 노드의 주소 (기존 대역)
kubectl get node $NEW_NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'; echo

# 그 노드에 Pod를 강제 배치
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: migrant
  labels: { run: migrant }
spec:
  nodeSelector: { iplab: "true" }
  containers:
    - name: migrant
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
EOF
kubectl wait --for=condition=Ready pod/migrant --timeout=120s
kubectl get pod migrant -o jsonpath='{.status.podIP}'; echo
```

예상:

```
10.0.x.x        ← 노드: 기존 서브넷
100.64.x.x      ← Pod: 신도시!
```

✅ **노드와 Pod의 주소 대역이 갈라졌습니다** — 본 서브넷의 IP 압박에서 Pod가 해방됐습니다. 통신도 확인:

```bash
kubectl exec migrant -- wget -qO- -T5 http://kubernetes.default.svc 2>&1 | head -1 || echo "(403이면 정상 — 도달은 됐습니다)"
```

## Step 7. 밀도의 대가 확인 (theory §4의 주의)

```bash
kubectl get node $NEW_NODE -o jsonpath='{.status.allocatable.pods}'; echo
```

custom networking은 primary ENI를 Pod에 안 쓰므로 같은 인스턴스라도 max-pods가 **줄어듭니다** — 그래서 프로덕션 설계는 여기에 prefix delegation을 얹어 밀도를 회복합니다(07). "영토는 넓히고 밀도는 prefix로" — 두 기술이 세트인 이유.

## 정리 — 원복이 곧 시험입니다

```bash
bash cleanup.sh    # 노드그룹 → env 원복 → ENIConfig → 서브넷 → CIDR 해제 (역순 해체)
```
