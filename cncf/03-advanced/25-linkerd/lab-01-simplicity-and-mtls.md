# Lab 01 — 설치·주입·자동 mTLS: "설정이 없다"를 체험합니다

24(Istio)에서 한 것과 같은 일을 Linkerd로 하며, 무엇을 덜 설정하는지 봅니다.

전제: kind, kubectl, linkerd CLI(`curl -sL https://run.linkerd.io/install | sh` 후 PATH).

## Step 1. 사전 점검과 설치

```bash
kind create cluster --name linkerd -q

linkerd check --pre
# CRD 먼저, 그다음 control plane
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
```

✅ `linkerd check`가 설치를 검증합니다 — Istio의 `istioctl install`에 대응하되, 이후 **설정할 CRD가 거의 없습니다**(theory §3).

## Step 2. 앱 배포 + 주입 — 어노테이션 하나

```bash
kubectl create ns demo
kubectl -n demo apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 2
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec: { containers: [{ name: c, image: hashicorp/http-echo, args: ["-text=web","-listen=:8080"] }] }
---
apiVersion: v1
kind: Service
metadata: { name: web }
spec: { selector: { app: web }, ports: [{ port: 8080 }] }
EOF
kubectl -n demo rollout status deploy/web --timeout=120s

# 주입: 어노테이션 추가 후 재배포 (또는 linkerd inject)
kubectl -n demo get deploy web -o yaml | linkerd inject - | kubectl apply -f -
kubectl -n demo rollout status deploy/web --timeout=120s

echo "=== Pod의 컨테이너 ==="
kubectl -n demo get pod -l app=web -o jsonpath='{.items[0].spec.containers[*].name}'; echo
```

예상: `c linkerd-proxy` — Rust 사이드카가 주입됐습니다. 크기를 비교해봅시다:

```bash
echo "=== linkerd-proxy 메모리 요청 (경량) ==="
kubectl -n demo get pod -l app=web -o jsonpath='{.items[0].spec.containers[?(@.name=="linkerd-proxy")].resources.requests.memory}'; echo
echo "→ Envoy 사이드카(수십 MB)보다 작습니다 (theory §2)"
```

## Step 3. 자동 mTLS — 설정한 적이 없습니다

```bash
kubectl -n demo run client --image=curlimages/curl -- sleep 3600
kubectl -n demo get deploy -o yaml 2>/dev/null | linkerd inject - 2>/dev/null | kubectl apply -f - 2>/dev/null || true
sleep 5

echo "=== 통신 확인 ==="
kubectl -n demo exec client -- curl -s web:8080 2>/dev/null || \
  (kubectl -n demo get po client -o yaml | linkerd inject - | kubectl apply -f - && sleep 20 && kubectl -n demo exec client -- curl -s web:8080)

cat <<'EOF'

★ Istio(24)와 비교:
  Istio: PeerAuthentication CRD로 mTLS 모드 지정, PERMISSIVE→STRICT 마이그레이션
  Linkerd: 아무 CRD도 안 만들었는데 메시 안 통신이 이미 mTLS
  → "설정 없이 안전"의 철학 (theory §3)
EOF
```

## Step 4. mTLS 확인 — linkerd viz

```bash
linkerd viz install | kubectl apply -f -
linkerd check
sleep 20

echo "=== edges: 연결과 mTLS 상태 ==="
linkerd -n demo viz edges deploy 2>/dev/null || linkerd viz -n demo edges deploy

echo ""
echo "=== SECURED 컬럼의 ✓가 mTLS ==="
```

예상: SRC→DST 연결에 `✓`(SECURED) — mTLS가 걸려 있습니다. ✅ 신원은 ServiceAccount 기반(theory §3), Istio의 SPIFFE와 유사하나 자동.

## Step 5. tap — 개별 요청 관찰 (tcpdump-for-requests)

```bash
# 백그라운드로 tap 켜고 요청 발생
(linkerd viz -n demo tap deploy/web 2>/dev/null | head -8 &) 
sleep 2
for i in $(seq 1 5); do kubectl -n demo exec client -- curl -s -o /dev/null web:8080; done
sleep 3

cat <<'EOF'
linkerd viz tap: 실시간 요청 스트림 (13의 조사 동선을 CLI로)
  req id=... :method=GET :path=/ ... tls=true
  → 개별 요청을 실시간으로, mTLS 여부까지
  ★ Istio는 config_dump·access log로 봐야 하는 것을 tap 한 줄로
EOF
```

## Step 6. 무엇을 안 했는가 — 단순함의 목록

```bash
cat <<'EOF'
=== 지금까지 만든 CRD 수 ===
Istio(24)에서 같은 지점까지: 
  PeerAuthentication, (DestinationRule, VirtualService for traffic)...
Linkerd에서:
  0개 (설치 + inject 어노테이션만)

이것이 "보이지 않는 메시"의 실체:
  mTLS를 원하면 → 설치하고 주입 (끝)
  골든 메트릭을 원하면 → viz 설치 (끝)
  → 대부분의 조직이 메시에서 실제로 원하는 것을 최소 설정으로

대가 (theory §5):
  세밀한 헤더 라우팅, 외부 인가(ext_authz), WASM 확장이 필요하면?
  → Linkerd는 답이 아닙니다. Istio 또는 Gateway API+Envoy
EOF
kubectl -n demo get virtualservices,destinationrules 2>/dev/null || echo "(Istio CRD 자체가 없습니다)"
```

## Step 7. 산출물

```markdown
# Linkerd 단순함 카드
- 설치: linkerd install (CRD → control plane)
- 주입: linkerd inject (어노테이션) → linkerd2-proxy(Rust) 사이드카
- 자동 mTLS: 설정 CRD 없이 메시 안 통신이 암호화·인증 (SA 기반 신원)
- 관측: linkerd viz (stat/top/tap/edges) — tap은 실시간 개별 요청
- 만든 CRD 수: Istio 대비 최소 (보이지 않는 메시)
- 대가: WASM·ext_authz·세밀한 라우팅 없음 (필요하면 Istio)
```

## 정리

lab-02에서 메트릭과 Istio 대비를 다룹니다. 유지.
