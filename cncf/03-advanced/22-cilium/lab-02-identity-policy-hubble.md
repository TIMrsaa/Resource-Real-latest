# Lab 02 — identity 기반 정책(L3/L4/L7)과 Hubble: 판정 지점의 관찰

정책을 세우고, 막히는 순간을 데이터 경로에서 직접 봅니다 — "왜 막혔는지"까지.

전제: lab-01의 클러스터(kind: cilium), Hubble relay 설치됨.

## Step 1. 관측 대상 앱과 Hubble CLI

```bash
kubectl create ns demo
kubectl apply -f - >/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: demo
  labels: { app: api }
spec:
  replicas: 1
  selector:
    matchLabels: { app: api }
  template:
    metadata:
      labels: { app: api }
    spec:
      containers:
        - name: nginx
          image: nginx
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: demo
spec:
  selector: { app: api }
  ports:
    - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: demo
  labels: { app: frontend }
spec:
  containers:
    - name: frontend
      image: nicolaka/netshoot
      command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: attacker
  namespace: demo
  labels: { app: attacker }
spec:
  containers:
    - name: attacker
      image: nicolaka/netshoot
      command: ["sleep", "3600"]
EOF
kubectl -n demo wait --for=condition=ready pod --all --timeout=120s

C() { kubectl -n kube-system exec ds/cilium -- "$@"; }
H() { kubectl -n kube-system exec ds/cilium -- hubble "$@"; }
```

## Step 2. 기본 개방 확인 + identity 관찰

```bash
echo "=== 정책 없음: 누구나 접근 가능 ==="
kubectl -n demo exec frontend -- curl -s -o /dev/null -w "frontend → api: %{http_code}\n" api
kubectl -n demo exec attacker -- curl -s -o /dev/null -w "attacker → api: %{http_code}\n" api

echo ""
echo "=== 각 Pod의 identity ==="
C cilium-dbg endpoint list 2>/dev/null | grep -E "demo|IDENTITY" | head -6 || \
  C cilium endpoint list | grep -E "demo|IDENTITY" | head -6
```

✅ 라벨이 다르면 identity가 다릅니다 — 정책의 주체가 준비됐습니다.

## Step 3. L3/L4 정책 — identity로 허용

```bash
kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: { name: api-l4, namespace: demo }
spec:
  endpointSelector: { matchLabels: { app: api } }
  ingress:
    - fromEndpoints: [{ matchLabels: { app: frontend } }]   # ★ IP가 아니라 라벨
      toPorts: [{ ports: [{ port: "80", protocol: TCP }] }]
EOF
sleep 8

kubectl -n demo exec frontend -- curl -s -o /dev/null -w "frontend → api: %{http_code}\n" --max-time 3 api
kubectl -n demo exec attacker -- curl -s -o /dev/null -w "attacker → api: %{http_code}\n" --max-time 3 api 2>&1 || echo "attacker → api: 차단됨 ✅"
```

예상: frontend 200, attacker 타임아웃. ✅ **identity 기반 집행**(theory §3).

## Step 4. Hubble — 판정 근거와 함께 보기

```bash
sleep 3
echo "=== 드롭된 플로우 (판정 근거 포함) ==="
H observe --namespace demo --verdict DROPPED --last 10 2>/dev/null | head -6

echo ""
echo "=== 허용된 플로우 ==="
H observe --namespace demo --verdict FORWARDED --last 5 2>/dev/null | head -4
```

예상: `attacker → api ... POLICY_DENIED DROPPED`. ✅ **어느 정책이 왜 떨궜는지**가 로그 한 줄에 — 04에서 말한 "판정 지점 = 관찰 지점"(eks 18의 Flow Logs가 답 못 하던 것).

```bash
echo ""
echo "=== 정책 결정 맵 직접 조회 ==="
EP=$(C cilium-dbg endpoint list -o json 2>/dev/null | python3 -c "
import json,sys
for e in json.load(sys.stdin):
    labels = e.get('status',{}).get('identity',{}).get('labels',[])
    if any('app=api' in l for l in labels): print(e['id']); break
" 2>/dev/null)
[ -n "$EP" ] && C cilium-dbg bpf policy get $EP 2>/dev/null | head -6 || \
  echo "(엔드포인트 ID 조회 실패 — cilium-dbg endpoint list로 수동 확인)"
```

## Step 5. L7 정책 — HTTP 메서드·경로 단위

```bash
kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: { name: api-l7, namespace: demo }
spec:
  endpointSelector: { matchLabels: { app: api } }
  ingress:
    - fromEndpoints: [{ matchLabels: { app: frontend } }]
      toPorts:
        - ports: [{ port: "80", protocol: TCP }]
          rules:
            http:
              - { method: "GET", path: "/$" }        # ★ GET / 만 허용
EOF
sleep 10

echo "GET / (허용되어야):"
kubectl -n demo exec frontend -- curl -s -o /dev/null -w "  %{http_code}\n" --max-time 3 api/
echo "POST / (거부되어야):"
kubectl -n demo exec frontend -- curl -s -o /dev/null -w "  %{http_code}\n" --max-time 3 -X POST api/
echo "GET /secret (거부되어야):"
kubectl -n demo exec frontend -- curl -s -o /dev/null -w "  %{http_code}\n" --max-time 3 api/secret

echo ""
echo "=== Hubble에서 L7 판정 보기 ==="
H observe --namespace demo --protocol http --last 6 2>/dev/null | head -6
```

예상: GET / 는 200, POST와 /secret은 **403**(Envoy가 거부). ✅ L7 정책이 동작합니다 — 그러나:

```bash
cat <<'EOF'
★ L7 정책의 대가 (theory §4):
  L3/L4는 순수 eBPF (커널에서 조회 후 즉시 판정)
  L7은 트래픽이 노드의 Envoy 프록시로 우회 → 파싱·판정 → 다시 전달
  → 지연 증가, CPU 사용, 그리고 Envoy가 새 장애 지점

원칙: L7 정책은 정말 필요한 엔드포인트에만.
      "전 서비스에 L7 정책"은 eBPF의 성능 이점을 스스로 버리는 것
EOF
```

## Step 6. toFQDNs — DNS 기반 egress (20과 결합)

```bash
kubectl apply -f - <<'EOF'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: { name: egress-fqdn, namespace: demo }
spec:
  endpointSelector: { matchLabels: { app: frontend } }
  egress:
    - toEndpoints: [{ matchLabels: { "k8s:io.kubernetes.pod.namespace": kube-system, "k8s:k8s-app": kube-dns } }]
      toPorts:
        - ports: [{ port: "53", protocol: UDP }]
          rules: { dns: [{ matchPattern: "*" }] }     # DNS 프록시가 응답을 관찰
    - toFQDNs: [{ matchName: "example.com" }]          # ★ 이 도메인만 허용
EOF
sleep 10

echo "example.com (허용):"
kubectl -n demo exec frontend -- curl -s -o /dev/null -w "  %{http_code}\n" --max-time 5 http://example.com || echo "  (네트워크 환경에 따라)"
echo "다른 도메인 (거부되어야):"
kubectl -n demo exec frontend -- curl -s -o /dev/null -w "  %{http_code}\n" --max-time 5 http://neverssl.com 2>&1 || echo "  차단됨 ✅"

cat <<'EOF'

toFQDNs의 동작 (theory §4):
  DNS 프록시가 Pod의 DNS 응답을 관찰 → 도메인의 IP를 학습 → 그 IP를 정책에 허용
  → "IP를 모르는 외부 서비스"에 정책을 쓸 수 있습니다
  대가: DNS 프록시 경유(20의 이름 해석 경로에 한 층 추가), TTL 관리
EOF
```

## Step 7. 관측 통합 — Hubble 메트릭

```bash
cat <<'EOF'
Hubble 메트릭 (06의 격자에 편입):
  hubble_drop_total{reason, protocol}       ← 왜 떨궜나 (정책? conntrack? unsupported?)
  hubble_flows_processed_total
  hubble_http_requests_total{method,status} ← L7 정책 사용 시

PromQL (11):
  sum by(reason)(rate(hubble_drop_total[5m]))   → 드롭 원인 분포
  → "정책 도입 후 드롭 증가"를 알람으로 (의도치 않은 차단 조기 발견)

★ 04의 사고 사례(NetworkPolicy가 장식이었던 조직)의 처방:
  POLICY_DENIED 카운터가 곧 "집행이 살아 있다"는 증거
EOF
H observe --verdict DROPPED --last 3 2>/dev/null | head -3 || true
```

## Step 8. 산출물

```markdown
# Cilium 정책·관찰 카드
- 정책 주체는 identity(라벨 집합) — IP가 아닙니다 (Pod 재생성에 무관)
- L3/L4: 순수 eBPF (빠름) / L7: Envoy 경유 (필요한 곳에만)
- toFQDNs: DNS 프록시가 도메인→IP 학습 → 외부 서비스 egress 정책
- Hubble: 판정 지점에서 판정 근거(POLICY_DENIED)와 함께 기록
- 알람: hubble_drop_total{reason="policy_denied"} — 집행의 생존 증거
- 진단: hubble observe --verdict DROPPED / cilium-dbg bpf policy get <ep>
```

## 정리

```bash
bash cleanup.sh
```
