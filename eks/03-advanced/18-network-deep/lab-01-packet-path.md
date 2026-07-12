# Lab 01 — 실측: veth, host route, ENI에서 경로를 눈으로 확인

theory §1~3의 그림을 실제 클러스터에서 재구성합니다. 도구는 두 개 — Pod 안(`kubectl exec`)과 노드 안(`kubectl debug node`).

## Step 1. 실험 배치 — 같은 노드 둘 + 다른 노드 하나

```bash
kubectl create ns netlab
NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))

for spec in "a ${NODES[0]}" "b ${NODES[0]}" "c ${NODES[1]}"; do
  set -- $spec
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pod-$1
  namespace: netlab
  labels: { run: pod-$1 }
spec:
  nodeName: $2                     # 스케줄러 우회 — 지정 노드에 강제 배치
  containers:
    - name: pod-$1
      image: ghcr.io/nicolaka/netshoot:latest
      command: ["sleep", "3600"]
EOF
done
kubectl wait --for=condition=Ready pod --all -n netlab --timeout=120s
kubectl get pods -n netlab -o wide     # a,b = 노드0 / c = 노드1, 각자의 IP 기록
A=$(kubectl get pod pod-a -n netlab -o jsonpath='{.status.podIP}')
B=$(kubectl get pod pod-b -n netlab -o jsonpath='{.status.podIP}')
C=$(kubectl get pod pod-c -n netlab -o jsonpath='{.status.podIP}')
echo "A=$A B=$B C=$C"
```

(netshoot: ping/traceroute/ss/tcpdump가 든 네트워크 진단 전용 이미지 — 38의 도구상자에 추가해둘 것)

## Step 2. Pod 안에서 — 세계가 이렇게 단순해 보입니다

```bash
kubectl exec -n netlab pod-a -- ip addr show eth0     # 자기 IP (VPC 대역!)
kubectl exec -n netlab pod-a -- ip route
```

예상:

```
default via 169.254.1.1 dev eth0     ← 가상 게이트웨이 — "전부 문 밖으로"
169.254.1.1 dev eth0
```

✅ Pod의 라우팅은 한 줄입니다 — 지능은 전부 **노드 쪽**에 있습니다.

## Step 3. 노드 안에서 — 안내판(host route)을 읽습니다

```bash
kubectl debug node/${NODES[0]} -it --image=ghcr.io/nicolaka/netshoot:latest -- bash
# (노드의 network namespace를 공유하는 Pod — 이하 그 셸 안에서)

ip route | grep -E "eni|veth" | head    # Pod IP마다 /32 → 각자의 veth
# 예: 10.0.34.12 dev eniXXXX scope link  ← "1004호는 이 문으로"

ip addr | grep -A1 "eni" | head         # veth들의 노드 쪽 끝
exit
```

✅ theory §1의 실물: **Pod IP마다 /32 host route** — CNI 플러그인이 Pod 생성 순간 심는 안내판입니다 (amazon-vpc-cni-k8s `routed-eni-cni-plugin`의 산출물).

## Step 4. 같은 노드 vs 다른 노드 — 홉 수로 구분

```bash
# 같은 노드 (A→B): 노드 안 왕복
kubectl exec -n netlab pod-a -- traceroute -n -m4 $B
# 다른 노드 (A→C): VPC를 건넙니다
kubectl exec -n netlab pod-a -- traceroute -n -m4 $C
```

예상: 둘 다 **한 홉 안팎으로 도착** — 오버레이 CNI라면 보였을 터널 홉이 없습니다. 그리고 지연 비교:

```bash
kubectl exec -n netlab pod-a -- ping -c5 -q $B    # 같은 노드: ~수십 µs
kubectl exec -n netlab pod-a -- ping -c5 -q $C    # 다른 노드: ~수백 µs (AZ 다르면 ms대)
```

✅ "같은 노드 > 같은 AZ > 다른 AZ"의 지연 사다리 — topology aware routing(14)이 절약하려는 게 바로 마지막 단입니다.

## Step 5. AWS 쪽 대조 — C의 IP는 어느 ENI에 사는가

```bash
aws ec2 describe-network-interfaces --region ap-northeast-2 \
  --filters "Name=addresses.private-ip-address,Values=$C" \
  --query 'NetworkInterfaces[0].{eni:NetworkInterfaceId,instance:Attachment.InstanceId,primary:PrivateIpAddress}' --output table
```

예상: 노드1 인스턴스에 붙은 ENI — C는 그 ENI의 **secondary IP**입니다(07의 회계 실물). ✅ "VPC가 Pod을 안다"의 증명: k8s 없이 AWS API만으로 Pod의 주소를 찾았습니다.

## Step 6. 외부로 — SNAT의 목격

```bash
# Pod가 밖에서 어떤 IP로 보이는가
kubectl exec -n netlab pod-a -- curl -s --max-time 5 https://checkip.amazonaws.com
```

예상: Pod IP도 노드 사설 IP도 아닌 **공인 IP** — 사설 서브넷이면 NAT GW의 EIP입니다. 경로: Pod($A) → 노드에서 SNAT(노드 primary IP) → NAT GW(다시 NAT) → 인터넷. theory §3의 이중 변신. (온프레로 Pod 실주소가 필요하면 EXTERNALSNAT — 16의 이주와 세트 논의)

## Step 7. 경로 지도 완성 (산출물)

```markdown
# 우리 클러스터 패킷 경로 지도 — 실측치 포함
① 같은 노드: veth→host route→veth (____µs)
② 노드 간:  veth→ENI→[VPC]→ENI(secondary IP)→veth (____µs, 캡슐화 없음 — traceroute로 확인)
③ 외부로:   SNAT(노드 IP)→NAT GW(공인 ____)
④ 유입:     ALB ip-mode → Pod ENI 직행 (14에서 실측)
```

## 정리

netlab의 Pod들은 lab-02에서 계속 씁니다. debug 노드 Pod 잔재만 정리:

```bash
kubectl get pods -A | grep node-debugger    # 있으면 삭제
```
