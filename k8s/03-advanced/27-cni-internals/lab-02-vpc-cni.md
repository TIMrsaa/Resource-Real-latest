# Lab 02 — VPC CNI 해부: ENI, IP 풀, 설정 체인

## Step 1. CNI 설정 파일 — 플러그인 체인 실물

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable -- \
  chroot /host cat /etc/cni/net.d/10-aws.conflist
```

예상 출력 (발췌):
```json
{ "cniVersion": "...", "name": "aws-cni",
  "plugins": [
    { "type": "aws-cni", ... },        ← 메인: ENI IP 할당+veth
    { "type": "egress-cni", ... },
    { "type": "portmap", ... }          ← hostPort 담당 보조
  ] }
```

✅ theory의 "체인" JSON이 실물로. kubelet(containerd)은 이 파일 순서대로 `/opt/cni/bin/`의 실행 파일들을 부릅니다.

```bash
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable -- \
  chroot /host ls /opt/cni/bin/
```

## Step 2. aws-node(ipamd) — IP 풀 관리자 관측

```bash
# ipamd가 들고 있는 IP 풀 현황 (introspection 엔드포인트)
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable -- \
  chroot /host curl -s http://localhost:61679/v1/enis | head -40
```

예상: ENI별로 할당된 secondary IP 목록과 어느 Pod에 배정됐는지의 JSON. **"미리 받아둔 IP 풀(warm pool)"** 의 실체입니다 — Pod 생성 시 AWS API를 기다리지 않고 즉시 줄 수 있는 이유.

## Step 3. AWS 쪽에서 같은 그림 보기

```bash
INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-2 \
  --filters "Name=private-dns-name,Values=$NODE" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ec2 describe-network-interfaces --region ap-northeast-2 \
  --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" \
  --query 'NetworkInterfaces[].{eni:NetworkInterfaceId,primary:PrivateIpAddress,secondaryCount:length(PrivateIpAddresses)}' \
  --output table
```

예상: 노드에 ENI 1~2개, 각각 secondary IP 여러 개 — **kubectl로 본 Pod IP들이 EC2 콘솔의 secondary IP와 일치**함을 대조해보세요:

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE | awk '{print $7}' | sort | head
```

✅ "Pod IP = ENI secondary IP" — VPC 네이티브의 결정적 증거. 보안그룹/Flow Logs가 Pod 트래픽을 그대로 보는 이유이기도 합니다.

## Step 4. 노드당 최대 Pod 수의 산수

```bash
kubectl get node $NODE -o jsonpath='{.status.allocatable.pods}'; echo
```

예상 (t3.medium):
```
17
```

산수의 출처: t3.medium = ENI 3개 × ENI당 IP 6개 = 18 - 1(노드 primary) = **17.** 인스턴스 타입표가 곧 Pod 밀도표입니다 — prefix delegation을 켜면 이 한계가 110으로 풀립니다 (eks 파트 16).

## Step 5. IP 고갈 시뮬레이션 (관찰만 — 공유 클러스터 주의)

t3.medium 2대 = 최대 34 Pod. 시스템 Pod를 빼면 ~20여 개 여유. replicas를 그 이상으로 올리면:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ip-eater
  labels: { app: ip-eater }
spec:
  replicas: 40
  selector:
    matchLabels: { app: ip-eater }
  template:
    metadata:
      labels: { app: ip-eater }
    spec:
      containers:
        - name: ip-eater
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sleep", "3600"]
EOF
sleep 30
kubectl get pods -l app=ip-eater --field-selector status.phase=Pending | wc -l
kubectl describe pod $(kubectl get pods -l app=ip-eater --field-selector status.phase=Pending -o jsonpath='{.items[0].metadata.name}') | tail -3
```

예상: 다수 Pending + `Too many pods` — **자원(CPU/메모리)이 남아도 IP가 없으면 못 띄웁니다.** EKS 용량 계획에서 IP가 1급 자원인 이유.

```bash
kubectl delete deployment ip-eater
```

## 정리

```bash
bash cleanup.sh
```
