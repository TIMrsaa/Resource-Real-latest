# Lab 01 — Corefile을 프로그램으로 읽고, ndots 증폭을 실측합니다

DNS 질의 하나가 몇 번의 왕복이 되는지 눈으로 세고, 그것을 줄입니다.

전제: kind, kubectl.

## Step 1. 클러스터와 Corefile

```bash
kind create cluster --name dns -q

echo "=== Corefile (플러그인 체인) ==="
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
```

체인을 읽어보세요: `errors → health → ready → kubernetes → prometheus → forward → cache → loop → reload → loadbalance`. ✅ `kubernetes` 플러그인이 답할 수 있으면 거기서 종료, 못 하면 `forward`가 상위 DNS로.

## Step 2. Pod의 resolv.conf — 증폭의 설계도

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: probe
  labels: { run: probe }
spec:
  restartPolicy: Never
  containers:
    - name: probe
      image: nicolaka/netshoot
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=ready pod/probe --timeout=120s

kubectl exec probe -- cat /etc/resolv.conf
```

예상:
```
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

✅ **ndots:5** — 점이 5개 미만인 이름은 search 도메인을 먼저 붙입니다(theory §3).

## Step 3. 증폭 실측 — 내부 이름 vs 외부 도메인

```bash
kubectl apply -f - >/dev/null <<'EOF'
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
EOF
sleep 10

echo "=== ① 내부 서비스 'web' (점 0개) ==="
kubectl exec probe -- sh -c 'dig +search +short web | head -2'
kubectl exec probe -- sh -c 'strace -f -e trace=sendto getent hosts web 2>&1 | grep -c sendto' 2>/dev/null || \
  echo "  (strace 없음 — 대신 tcpdump로 확인)"

echo ""
echo "=== ② 외부 도메인 'example.com' (점 1개 < 5) ==="
kubectl exec probe -- sh -c 'time (getent hosts example.com >/dev/null)' 2>&1 | tail -3
```

DNS 왕복을 직접 세어봅시다:

```bash
# CoreDNS의 로그를 켜서 질의를 관찰
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' > /tmp/Corefile.bak
kubectl -n kube-system patch cm coredns --type merge -p '{"data":{"Corefile":".:53 {\n    errors\n    log\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . /etc/resolv.conf\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'
kubectl -n kube-system rollout restart deploy/coredns
kubectl -n kube-system rollout status deploy/coredns --timeout=120s
sleep 5

echo "=== 외부 도메인 해석 시 실제 질의들 ==="
kubectl exec probe -- getent hosts example.com >/dev/null 2>&1
sleep 3
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=30 | grep -i "example.com" | head -8
```

예상: `example.com.default.svc.cluster.local`, `example.com.svc.cluster.local`, `example.com.cluster.local`, `example.com` — **네 번의 질의**(각각 A·AAAA면 여덟 번). ✅ theory §3의 증폭이 로그로.

## Step 4. 대응 ① — FQDN(끝에 점)

```bash
echo "=== 'example.com.' (FQDN — search 건너뜀) ==="
kubectl exec probe -- getent hosts example.com. >/dev/null 2>&1 || \
  kubectl exec probe -- dig +short example.com. >/dev/null
sleep 3
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20 | grep -c "example.com" || true
echo "→ 질의 횟수가 줄었습니다 (search 순회 생략)"
```

## Step 5. 대응 ② — dnsConfig로 ndots 낮추기

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: probe-low-ndots }
spec:
  containers:
    - name: c
      image: nicolaka/netshoot
      command: ["sleep","3600"]
  dnsConfig:
    options:
      - { name: ndots, value: "2" }     # ★ 점 2개 미만만 search 적용
EOF
kubectl wait --for=condition=ready pod/probe-low-ndots --timeout=120s
kubectl exec probe-low-ndots -- cat /etc/resolv.conf | grep ndots

kubectl exec probe-low-ndots -- getent hosts example.com >/dev/null 2>&1
sleep 3
echo "=== ndots:2 에서 example.com(점 1개) 질의 ==="
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=15 | grep "example.com" | head -3
```

예상: 점 1개는 여전히 2 미만이라 search를 탑니다... 점 2개 이상 이름(`api.example.com`)이면 즉시 외부로. ✅ **ndots 값과 도메인의 점 개수 관계**를 이해하는 것이 요점 — 대부분의 외부 도메인은 점 1~2개이므로 `ndots: 1`이 가장 효과적이지만, 내부 짧은 이름(`web`) 해석이 깨질 수 있으니 앱별로 판단.

```bash
cat <<'EOF'
정리:
  ndots:5 (기본)  → 내부 짧은 이름 편의, 외부 도메인 증폭
  ndots:2         → 절충 (api.example.com 은 즉시 외부)
  ndots:1         → 외부 최적, 내부는 반드시 FQDN 사용
  ★ 외부 API 호출이 많은 앱만 선별적으로 낮춰라 (전역 변경은 위험)
EOF
```

## Step 6. 레코드 종류 — Headless와 SRV

```bash
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sts-like
  labels: { app: sts-like }
spec:
  replicas: 3
  selector:
    matchLabels: { app: sts-like }
  template:
    metadata:
      labels: { app: sts-like }
    spec:
      containers:
        - name: nginx
          image: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: headless
spec:
  clusterIP: None                    # ★ headless — 가상 IP 없이 Pod IP들이 그대로
  selector: { app: sts-like }
  ports:
    - port: 80
EOF
sleep 15

echo "=== ClusterIP Service: 하나의 IP ==="
kubectl exec probe -- dig +short web.default.svc.cluster.local

echo ""
echo "=== Headless Service: 모든 Pod IP ==="
kubectl exec probe -- dig +short headless.default.svc.cluster.local

echo ""
echo "=== SRV 레코드 (명명된 포트) ==="
kubectl exec probe -- dig +short SRV _http._tcp.web.default.svc.cluster.local 2>/dev/null || \
  echo "  (포트에 name이 있어야 SRV가 생깁니다)"
```

✅ Headless가 **모든 Pod IP**를 반환하는 것 — StatefulSet의 안정적 네트워크 ID와 클라이언트 사이드 로드밸런싱(gRPC)의 기반(theory §2, 09와 연결).

## Step 7. Corefile 복원 및 산출물

```bash
kubectl -n kube-system patch cm coredns --type merge \
  -p "{\"data\":{\"Corefile\":$(python3 -c "import json,sys; print(json.dumps(open('/tmp/Corefile.bak').read()))")}}"
kubectl -n kube-system rollout restart deploy/coredns >/dev/null
```

```markdown
# ndots 카드
- Pod resolv.conf: search 3개 + ndots:5
- 점 < ndots → search 도메인을 먼저 시도 (내부 이름은 1회, 외부는 4회)
- A+AAAA 이중 질의 → 최대 8 왕복
- 대응: FQDN(끝점) / dnsConfig ndots / autopath / NodeLocal 캐시
- 측정법: CoreDNS의 log 플러그인 켜고 질의 세기
```

## 정리

lab-02에서 계속. 유지.
