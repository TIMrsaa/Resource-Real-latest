# Lab 02 — Cilium 시식: CNI 교체, NetworkPolicy, Hubble로 패킷 관찰

kind의 기본 CNI를 끄고 Cilium을 시공사로 투입합니다 — eBPF 데이터 경로에서 정책과 관찰이 어떻게 한 몸인지 맛봅니다. (심층 해부는 22 — 여기서는 카테고리의 존재 이유 체험.)

전제: kind, kubectl, helm. 메모리 8GB 권장.

## Step 1. CNI 없는 클러스터 — 시공사가 없으면 생기는 일

```bash
kind create cluster --name cilium --config - <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true        # kindnet 끔 — CNI 부재 상태로
nodes: [{ role: control-plane }, { role: worker }]
EOF

kubectl get nodes                 # NotReady — CNI가 없으니!
kubectl -n kube-system get pods | grep -E "coredns" | head -2   # Pending — Pod IP를 줄 자가 없습니다
```

예상: 노드 NotReady, CoreDNS Pending. ✅ **CNI가 "있으면 좋은 것"이 아니라 노드 Ready의 전제 조건**임을 몸으로 — Pod에 IP와 배관을 만드는 시공사가 없으면 도시가 안 섭니다.

## Step 2. Cilium 투입

```bash
helm repo add cilium https://helm.cilium.io >/dev/null 2>&1
helm install cilium cilium/cilium -n kube-system \
  --set kubeProxyReplacement=true \
  --set hubble.relay.enabled=true --set hubble.ui.enabled=false >/dev/null
kubectl -n kube-system rollout status ds/cilium --timeout=300s
kubectl get nodes                 # Ready로 전환!
```

예상: cilium DaemonSet이 뜨자 노드 Ready, CoreDNS Running. `kubeProxyReplacement=true` — **kube-proxy의 iptables 체인 대신 eBPF 해시맵**이 Service 라우팅을 맡습니다(theory §5).

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --brief 2>/dev/null || \
  kubectl -n kube-system exec ds/cilium -- cilium status --brief
```

## Step 3. 관찰 대상 앱 + 기본 개방 확인

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: { app: web }
spec:
  replicas: 1
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
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  labels: { run: client }
spec:
  restartPolicy: Never
  containers:
    - name: client
      image: busybox
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=ready pod --all --timeout=120s

kubectl exec client -- wget -qO- --timeout=3 web | head -2
```

예상: nginx 응답 — k8s의 기본값은 전면 개방(모든 Pod가 모든 Pod에게).

## Step 4. NetworkPolicy — 거부가 정책이 되는 순간

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-lockdown }
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: [Ingress]
  ingress:
    - from: [{ podSelector: { matchLabels: { role: allowed } } }]
EOF

kubectl exec client -- wget -qO- --timeout=3 web 2>&1 | tail -1   # 차단!
kubectl label pod client role=allowed
sleep 3
kubectl exec client -- wget -qO- --timeout=3 web | head -2         # 허용
```

예상: 라벨 전 timeout, 라벨 후 응답. ✅ Flannel이었다면 이 정책은 **조용히 무시**됐습니다(정책 미지원 CNI — 선택 축 ②의 실감). Cilium은 eBPF 데이터 경로에서 집행합니다.

## Step 5. Hubble — 데이터 경로 안의 관찰

```bash
# 차단 상태를 다시 만들고 그 순간을 "본다"
kubectl label pod client role-
kubectl exec client -- wget -qO- --timeout=2 web 2>/dev/null || true

kubectl -n kube-system exec ds/cilium -- hubble observe --last 20 2>/dev/null | \
  grep -E "web|DROPPED|FORWARDED" | tail -6
```

예상: `client -> web ... POLICY_DENIED DROPPED` 류의 플로우 기록 — **누가 누구에게, 어느 정책이 떨궜는지**가 로그 한 줄로. ✅ theory §5의 핵심: 별도 에이전트가 패킷을 복사해 추측하는 게 아니라, **지나가는 자리(eBPF)에서 판정과 관찰이 동시에** — eks 18에서 Flow Logs의 사각을 고민했던 그 문제의 다른 답입니다.

## Step 6. 산출물 — 시식 결론 카드

```markdown
# Cilium 시식에서 확인한 것
- CNI = 노드 Ready의 전제 (부재 시 도시 정지 — Step 1)
- kubeProxyReplacement: iptables 체인 → eBPF 맵 (Service 5천 개 문제의 답)
- NetworkPolicy: CNI가 집행자 — 미지원 CNI에선 정책이 장식 (Step 4)
- Hubble: 판정 지점 = 관찰 지점 — "왜 안 돼?"가 grep 한 번 (Step 5)
- 미뤄둔 질문(→ 22 심층): eBPF 프로그램은 어디에 어떻게 붙나, identity 기반 정책의 내부, ambient/메시와의 경계
```

## 정리

```bash
bash cleanup.sh
```
