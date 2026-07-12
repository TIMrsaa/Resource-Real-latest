# Lab 01 — ENI/IP 실측과 ipamd 관측

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 내 노드의 천장 계산 → 실측 대조

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
ITYPE=$(kubectl get node $NODE -o jsonpath='{.metadata.labels.node\.kubernetes\.io/instance-type}')
echo "타입: $ITYPE"
# kubelet이 보고하는 실제 maxPods
kubectl get node $NODE -o jsonpath='{.status.allocatable.pods}'; echo
```

theory §1의 공식으로 손 계산 → 일치 확인 (t3.medium이면 17). **CPU/메모리보다 먼저 닿는 천장**이 이 숫자입니다.

## Step 2. ENI의 실물 — EC2에서 보기

```bash
IID=$(aws ec2 describe-instances --region $AWS_REGION \
  --filters "Name=private-dns-name,Values=$NODE" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ec2 describe-network-interfaces --region $AWS_REGION \
  --filters "Name=attachment.instance-id,Values=$IID" \
  --query 'NetworkInterfaces[].{eni:NetworkInterfaceId,primary:PrivateIpAddress,secondaryCount:length(PrivateIpAddresses)}' \
  --output table
```

✅ 노드에 ENI가 여러 개, 각 ENI에 secondary IP 묶음 — **그 secondary들이 Pod에게 나눠줄 좌석표**입니다. Pod IP와 대조:

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE | head -5
aws ec2 describe-network-interfaces --region $AWS_REGION \
  --filters "Name=attachment.instance-id,Values=$IID" \
  --query 'NetworkInterfaces[].PrivateIpAddresses[].PrivateIpAddress' | head -15
```

✅ Pod IP가 ENI의 secondary IP 목록 안에 있습니다 — "Pod IP = 진짜 VPC IP"(k8s 27)의 재확인, 이번엔 할당 장부까지.

## Step 3. ipamd 메트릭 — 재고 장부 열람

```bash
AWSNODE=$(kubectl get pods -n kube-system -l k8s-app=aws-node \
  --field-selector spec.nodeName=$NODE -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $AWSNODE -c aws-node -- \
  curl -s localhost:61678/v1/enis | python3 -m json.tool | head -30
```

예상(요약): ENI별 IP 목록과 할당 여부 — **ipamd가 쥔 재고 장부의 원본**.

```bash
# 핵심 수치만
kubectl exec -n kube-system $AWSNODE -c aws-node -- curl -s localhost:61678/metrics \
  | grep -E "^awscni_(total|assigned)_ip_addresses"
```

✅ `total - assigned` = warm pool(여분) — theory §2의 trade-off가 숫자로 보입니다. 이 두 메트릭이 운영 대시보드(12)에 올라가야 할 것들.

## Step 4. IP 소비 폭주 실험 — warm pool이 일하는 모습

터미널 1 (감시):
```bash
watch -n3 "kubectl exec -n kube-system $AWSNODE -c aws-node -- curl -s localhost:61678/metrics | grep -E '^awscni_(total|assigned)_ip'"
```

터미널 2 (그 노드에 Pod 쏟기):
```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ip-eater
  labels: { app: ip-eater }
spec:
  replicas: 10
  selector:
    matchLabels: { app: ip-eater }
  template:
    metadata:
      labels: { app: ip-eater }
    spec:
      nodeSelector:
        kubernetes.io/hostname: $NODE       # 관찰 중인 그 노드에만 배치
      containers:
        - name: ip-eater
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sleep", "3600"]
EOF
```

관찰 포인트: assigned가 오르고 → 풀이 얇아지면 total도 점프(ipamd가 ENI/IP 추가 — EC2 API 호출). 서브넷 가용 IP도 같이 줄어듭니다:

```bash
SUBNET=$(aws ec2 describe-instances --instance-ids $IID --region $AWS_REGION \
  --query 'Reservations[0].Instances[0].SubnetId' --output text)
aws ec2 describe-subnets --subnet-ids $SUBNET --region $AWS_REGION \
  --query 'Subnets[0].AvailableIpAddressCount'
```

✅ **Pod 증가 → 노드 IP 재고 → 서브넷 잔량**의 사슬을 실측했습니다 — 16(IP 고갈)에서 이 사슬의 끝을 일부러 보게 됩니다.

## Step 5. ipamd 로그 — 진단의 원천

```bash
kubectl exec -n kube-system $AWSNODE -c aws-node -- \
  tail -5 /host/var/log/aws-routed-eni/ipamd.log 2>/dev/null \
  || kubectl logs -n kube-system $AWSNODE -c aws-node --tail=5
```

✅ "Assigned IP / Added ENI / DataStore" 류의 라인 — k8s 27에서 "CNI 문제의 3번째 진단처"라 한 그 로그의 실물. `failed to assign an IP`가 여기 찍히면 = 고갈(16).

## 정리

```bash
kubectl delete deployment ip-eater
```
