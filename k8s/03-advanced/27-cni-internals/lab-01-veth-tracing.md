# Lab 01 — Pod의 랜선(veth) 찾기와 패킷 추적

## Step 0. 추적 대상

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: net-target
  labels: { run: net-target }
spec:
  containers:
    - name: net-target
      image: registry.k8s.io/e2e-test-images/agnhost:2.53
      args: ["netexec", "--http-port=8080"]
EOF
kubectl wait --for=condition=Ready pod/net-target
POD_IP=$(kubectl get pod net-target -o jsonpath='{.status.podIP}')
NODE=$(kubectl get pod net-target -o jsonpath='{.spec.nodeName}')
echo "pod=$POD_IP node=$NODE"
```

## Step 1. Pod 쪽 끝: eth0의 정체

```bash
# eth0의 인터페이스 인덱스와 "페어 상대"의 인덱스(@ifXX) 확인
kubectl exec net-target -- ip addr show eth0
```

예상 출력:
```
3: eth0@if12: <BROADCAST,...> ...      ← "@if12" = 내 랜선의 반대쪽 끝은 노드의 12번 인터페이스!
    inet 192.168.x.x/32 ...
```

## Step 2. 노드 쪽 끝 찾기

```bash
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable
```

노드 셸에서 (`chroot /host` 후):

```sh
chroot /host
# 12번 인터페이스 (위에서 본 @if 번호로)
ip addr | grep -A1 "^12:"
```

예상 출력:
```
12: enixxxxxxxxx@if3: ...     ← 노드 쪽 끝! (@if3 = Pod 쪽 eth0의 인덱스)
```

✅ **랜선의 양 끝을 다 찾았습니다**: Pod의 `eth0@if12` ↔ 노드의 `enixxx@if3`. 서로의 인덱스를 가리키는 구조가 veth 페어의 지문입니다.

## Step 3. 라우팅 — "그 Pod 찾아가는 법"

```sh
ip route | grep <POD_IP>
```

예상 출력:
```
192.168.x.x dev enixxxxxxxxx scope link     ← "이 IP는 저 veth로 보내라"
```

✅ 노드 안에서 Pod IP로 향하는 패킷의 마지막 홉이 이 한 줄입니다. CNI ADD가 한 일 = veth 생성 + IP 부여 + **이 라우트 등록**.

## Step 4. 같은 노드 Pod 간 통신 추적 (tcpdump)

```sh
# 노드에서 veth 인터페이스를 도청
timeout 15 tcpdump -i enixxxxxxxxx -n 'tcp port 8080' &
```

다른 터미널에서:
```bash
kubectl run net-client --rm -it --restart=Never \
  --image=public.ecr.aws/docker/library/busybox:stable -- \
  wget -qO- http://$POD_IP:8080/hostname
```

노드 셸 예상 출력:
```
IP 192.168.y.y.xxxxx > 192.168.x.x.8080: Flags [S] ...    ← SYN이 veth를 지나갑니다!
IP 192.168.x.x.8080 > 192.168.y.y.xxxxx: Flags [S.] ...
```

✅ **패킷이 정말 그 랜선을 지나는** 것을 도청으로 확인 — "Pod 네트워크가 안 돼요"의 최종 진단법이 이 tcpdump입니다 (어느 구간까지 패킷이 오는지 자르기).

## Step 5. ARP/이웃 테이블 — 노드 간의 경우

```sh
ip neigh | head -5     # 노드가 아는 이웃 (VPC CNI에선 ENI 게이트웨이 등)
ip route | grep -v eni | head -8    # 기본 라우팅 — VPC CIDR이 그냥 eth0으로 (캡슐화 없음!)
exit; exit
```

✅ 오버레이 CNI였다면 여기 vxlan 인터페이스/터널 라우트가 보였을 것입니다. VPC CNI의 라우팅 테이블이 "평범한" 것 자체가 — Pod IP가 진짜 VPC 시민이라는 증거.

## 정리

```bash
kubectl delete pod net-target --ignore-not-found
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
```
