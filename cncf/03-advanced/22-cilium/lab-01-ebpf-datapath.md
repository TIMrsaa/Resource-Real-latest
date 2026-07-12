# Lab 01 — eBPF 데이터 경로를 열어보다: 프로그램, 맵, 그리고 kube-proxy의 부재

커널에 붙은 프로그램과 그것이 조회하는 맵을 직접 봅니다 — "iptables 규칙 대신 해시맵"의 실물.

전제: kind, kubectl, helm, docker. 메모리 8GB+.

## Step 1. kube-proxy 없는 클러스터

```bash
cat > /tmp/kind-cilium.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true      # CNI 없음 (Cilium이 맡습니다)
  kubeProxyMode: none          # ★ kube-proxy도 없습니다!
nodes:
  - role: control-plane
  - role: worker
EOF
kind create cluster --name cilium --config /tmp/kind-cilium.yaml -q

kubectl get nodes        # NotReady (CNI 없음)
kubectl -n kube-system get ds kube-proxy 2>/dev/null || echo "→ kube-proxy가 없다"
```

## Step 2. Cilium 설치 — kube-proxy 대체 모드

```bash
API_SERVER_IP=$(docker inspect cilium-control-plane -f '{{ .NetworkSettings.Networks.kind.IPAddress }}')

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1
helm install cilium cilium/cilium -n kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=$API_SERVER_IP \
  --set k8sServicePort=6443 \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=false \
  --set operator.replicas=1 >/dev/null
kubectl -n kube-system rollout status ds/cilium --timeout=300s
kubectl get nodes      # Ready!

kubectl -n kube-system exec ds/cilium -- cilium-dbg status --brief 2>/dev/null || \
  kubectl -n kube-system exec ds/cilium -- cilium status --brief
```

✅ CNI와 kube-proxy가 동시에 해결됐습니다 — 같은 eBPF 데이터 경로에서.

## Step 3. 커널에 붙은 eBPF 프로그램 보기

```bash
docker exec cilium-worker sh -c '
echo "=== 로드된 eBPF 프로그램 (tc/XDP 훅) ==="
bpftool prog show 2>/dev/null | grep -E "sched_cls|xdp|cgroup" | head -6 || echo "(bpftool 없음 — 노드 이미지에 따라)"
' 2>/dev/null || \
kubectl -n kube-system exec ds/cilium -- sh -c '
echo "=== cilium-dbg로 본 데이터 경로 ==="
cilium-dbg status | grep -A5 "KubeProxyReplacement" 2>/dev/null || cilium status | grep -A5 "KubeProxyReplacement"
'
```

```bash
echo ""
echo "=== tc에 붙은 필터 (Pod의 veth에) ==="
kubectl -n kube-system exec ds/cilium -- sh -c 'tc filter show dev cilium_host ingress 2>/dev/null | head -4' || \
  echo "(권한/도구에 따라 다름 — 아래 맵 조회로 대체)"
```

## Step 4. eBPF 맵 — 상태가 사는 곳

```bash
C() { kubectl -n kube-system exec ds/cilium -- "$@"; }

kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: { app: web }
spec:
  replicas: 2
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: nginx
          image: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector: { app: web }
  ports:
    - port: 80
EOF
kubectl wait --for=condition=available deploy/web --timeout=120s
sleep 10

echo "=== ① Service 맵 (kube-proxy의 iptables 규칙을 대체) ==="
C cilium-dbg bpf lb list 2>/dev/null | head -8 || C cilium bpf lb list | head -8

echo ""
echo "=== ② 엔드포인트(Pod) 목록 ==="
C cilium-dbg endpoint list 2>/dev/null | head -6 || C cilium endpoint list | head -6

echo ""
echo "=== ③ ipcache: IP → identity 매핑 ==="
C cilium-dbg bpf ipcache list 2>/dev/null | head -6 || C cilium bpf ipcache list | head -6
```

✅ **iptables 규칙이 아니라 맵의 엔트리**입니다(theory §2). Service를 수천 개 만들어도 조회는 O(1) — 04에서 말한 지각 변동의 실체.

```bash
echo ""
echo "=== 비교: iptables 규칙은 몇 개인가요? ==="
docker exec cilium-worker sh -c 'iptables -t nat -L -n 2>/dev/null | wc -l' || echo "(iptables 거의 비어 있음)"
echo "→ kube-proxy가 있었다면 Service마다 수 개의 규칙이 쌓였을 자리"
```

## Step 5. identity — 라벨이 숫자가 됩니다

```bash
echo "=== 클러스터의 identity 목록 ==="
C cilium-dbg identity list 2>/dev/null | head -10 || C cilium identity list | head -10

echo ""
echo "=== web Pod의 identity ==="
POD_IP=$(kubectl get pod -l app=web -o jsonpath='{.items[0].status.podIP}')
echo "Pod IP: $POD_IP"
C cilium-dbg bpf ipcache get $POD_IP 2>/dev/null || C cilium bpf ipcache get $POD_IP 2>/dev/null || \
  C cilium-dbg bpf ipcache list | grep "$POD_IP"
```

✅ Pod IP가 identity 번호로 매핑됩니다. 이제 Pod를 재생성해봅시다:

```bash
OLD_ID=$(C cilium-dbg bpf ipcache list 2>/dev/null | grep "$POD_IP" | awk '{print $2}' | head -1)
kubectl delete pod -l app=web --wait=true >/dev/null
sleep 20
NEW_IP=$(kubectl get pod -l app=web -o jsonpath='{.items[0].status.podIP}')
NEW_ID=$(C cilium-dbg bpf ipcache list 2>/dev/null | grep "$NEW_IP" | awk '{print $2}' | head -1)

echo "재생성 전: IP=$POD_IP identity=$OLD_ID"
echo "재생성 후: IP=$NEW_IP identity=$NEW_ID"
echo "→ IP는 바뀌었지만 identity는 같습니다 (라벨이 같으므로) — 정책이 그대로 유효 ✅"
```

✅ theory §3의 핵심: **IP가 아니라 라벨 집합이 정책의 주체**입니다.

## Step 6. socket-level LB — 홉이 사라집니다

```bash
cat <<'EOF'
kubeProxyReplacement=true 의 socket LB:
  전통: Pod가 ClusterIP(10.96.x.x)로 connect → 패킷이 나가며 DNAT → 백엔드 IP
  Cilium: Pod의 connect() 시스템콜 시점(cgroup/connect4 훅)에서
          목적지를 이미 백엔드 Pod IP로 바꿉니다
  → 패킷 자체가 처음부터 백엔드로 향합니다 (DNAT 홉 없음, conntrack 항목 감소)
  → 20의 5초 지연(conntrack DNAT 경쟁)이 구조적으로 완화되는 이유
EOF

C cilium-dbg status 2>/dev/null | grep -iE "socket|host routing|bpf" | head -4 || \
  C cilium status | grep -iE "socket|host routing" | head -4
```

## Step 7. 산출물

```markdown
# Cilium 데이터 경로 카드
- eBPF 프로그램: tc ingress/egress, cgroup connect, (XDP)
- 상태는 맵에: cilium_lb4_services(Service), cilium_ipcache(IP→identity),
              cilium_policy_*(정책), cilium_ct4_global(conntrack)
- agent가 K8s를 watch → 맵 갱신 / 커널 프로그램은 조회만
- identity: 라벨 집합의 해시 — Pod 재생성·IP 변경에 불변
- kube-proxy 대체: iptables 체인 → 맵 O(1) + socket LB(DNAT 홉 제거)
- 진단 도구: cilium-dbg bpf lb list / endpoint list / ipcache list / identity list
```

## 정리

lab-02에서 계속. 유지.
