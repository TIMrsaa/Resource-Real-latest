# Lab 02 — 골든 메트릭과 트래픽 분할, 그리고 Istio와의 직접 대비

자동 관측을 확인하고, 카나리를 걸어본 뒤, 24와 나란히 놓아 선택 기준을 세웁니다.

전제: lab-01의 클러스터(kind: linkerd), viz 설치됨.

## Step 1. 골든 메트릭 — 자동 생성

```bash
# 트래픽을 발생시킵니다
for i in $(seq 1 30); do kubectl -n demo exec client -- curl -s -o /dev/null web:8080; done
sleep 5

echo "=== linkerd viz stat: 골든 메트릭 (성공률·RPS·지연) ==="
linkerd viz -n demo stat deploy 2>/dev/null

cat <<'EOF'

컬럼 (theory §4):
  SUCCESS  성공률 (2xx·3xx)
  RPS      초당 요청
  LATENCY  P50 / P95 / P99
  MESHED   메시된 Pod 수
  TLS      mTLS 비율

★ 설정한 적 없습니다 — 사이드카가 모든 트래픽을 보므로 자동
  (Istio도 같지만, Linkerd는 카디널리티를 의도적으로 억제 — 24의 폭발 회피)
EOF
```

## Step 2. top — 실시간 요청 분석 (13의 조사 동선)

```bash
(linkerd viz -n demo top deploy/web 2>/dev/null | head -10 &)
sleep 2
for i in $(seq 1 20); do
  kubectl -n demo exec client -- curl -s -o /dev/null web:8080
  kubectl -n demo exec client -- curl -s -o /dev/null web:8080/notfound
done
sleep 3
echo "→ 경로별 성공률·지연이 실시간으로 (13의 지연 히스토그램·조사를 CLI로)"
```

## Step 3. 트래픽 분할 — Gateway API로 카나리

```bash
# v2 배포
kubectl -n demo apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web-v2 }
spec:
  replicas: 1
  selector: { matchLabels: { app: web-v2 } }
  template:
    metadata: { labels: { app: web-v2 } }
    spec: { containers: [{ name: c, image: hashicorp/http-echo, args: ["-text=web-v2","-listen=:8080"] }] }
---
apiVersion: v1
kind: Service
metadata: { name: web-v2 }
spec: { selector: { app: web-v2 }, ports: [{ port: 8080 }] }
EOF
kubectl -n demo get deploy web-v2 -o yaml | linkerd inject - | kubectl apply -f -
kubectl -n demo rollout status deploy/web-v2 --timeout=120s

# HTTPRoute로 90/10 분할 (Gateway API — 04)
kubectl -n demo apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: web-split }
spec:
  parentRefs: [{ name: web, kind: Service, group: core, port: 8080 }]
  rules:
    - backendRefs:
        - { name: web, port: 8080, weight: 90 }
        - { name: web-v2, port: 8080, weight: 10 }
EOF
sleep 8

echo "=== 90/10 분할 확인 ==="
for i in $(seq 1 30); do kubectl -n demo exec client -- curl -s web:8080; echo; done | sort | uniq -c
```

예상: web ~27, web-v2 ~3. ✅ **Gateway API 표준(HTTPRoute)으로 카나리** — Istio(24)는 자체 VirtualService, Linkerd는 표준으로 수렴(theory §5, 04의 Gateway API). 17의 Argo Rollouts가 이 HTTPRoute를 조작해 자동화합니다.

## Step 4. Istio와의 직접 대비 — 같은 작업, 다른 부담

```bash
cat <<'EOF'
=== 24(Istio) vs 25(Linkerd) — 같은 3가지 작업 ===

[mTLS 켜기]
  Istio:   PeerAuthentication CRD, PERMISSIVE→STRICT 마이그레이션
  Linkerd: 설치+주입만 (CRD 0개, 자동)

[카나리 90/10]
  Istio:   VirtualService + DestinationRule (자체 CRD 2개)
  Linkerd: HTTPRoute (Gateway API 표준 1개)

[골든 메트릭]
  Istio:   자동, 단 카디널리티 폭발 주의 (telemetry API로 억제)
  Linkerd: 자동, 카디널리티 의도적 억제 + viz stat/top/tap

[사이드카 크기]
  Istio:   Envoy 수십 MB (범용)
  Linkerd: linkerd2-proxy 수 MB (전용 Rust)

[할 수 있는 것의 최대치]
  Istio:   WASM·ext_authz·세밀한 프로토콜·ambient — 최대
  Linkerd: 핵심만 — 그 이상이 필요하면 Istio
EOF
```

## Step 5. 선택 판단 — 48의 예고

```bash
cat <<'EOF'
=== 메시 선택 결정 트리 ===

메시가 정말 필요한가? (eks 20, 24)
  mTLS·트래픽관리·관측 중 몇 개가 실제 요구?
  1개 → 가벼운 대안 (Cilium 암호화, Argo Rollouts+Gateway API)
  ↓ (2~3개 겹침)

이미 Cilium CNI인가요?
  Yes → Cilium Service Mesh 검토 (22, 사이드카 없는 mTLS)
  ↓

원하는 것이 "mTLS + 골든 메트릭 + 간단한 분할"인가요?
  Yes + 운영 최소화 우선 → Linkerd
  ↓

복잡한 트래픽 관리(세밀 라우팅·외부 인가·WASM)가 필요한가?
  Yes → Istio (사이드카 또는 ambient)
  대규모 비용 최적화 필요 → Istio ambient

★ "더 많은 기능"이 우월이 아닙니다 — 운영하지 않을 기능은 부채 (24의 사고)
  둘 다 CNCF Graduated, 둘 다 옳습니다, 다른 질문에 답할 뿐
EOF
```

## Step 6. 단순함의 대가 확인

```bash
cat <<'EOF'
Linkerd가 못 하는(또는 어려운) 것:
  - 외부 인가 서비스 연동(ext_authz → OPA) — Istio는 필터로 간단
  - WASM 플러그인 확장
  - 세밀한 헤더 조작·복잡한 매칭
  - 비HTTP 프로토콜의 L7 처리 (제한적)
  - 멀티클러스터의 고급 시나리오 (있지만 Istio가 더 성숙한 영역도)

→ 이것이 필요하면 Linkerd의 단순함은 오히려 제약
  "단순함은 그 단순함이 충분할 때만 강점" (25의 핵심)
EOF
```

## Step 7. 산출물 — 메시 3종 비교표

```markdown
# 메시 선택 (04·22·24·25 종합)
| | Istio 사이드카 | Istio ambient | Linkerd | Cilium Mesh |
|---|---|---|---|---|
| 데이터플레인 | Envoy/Pod | ztunnel+waypoint | Rust/Pod | eBPF+Envoy(L7) |
| 기능 | 최대 | 최대(선택적 L7) | 핵심 | CNI 통합 |
| 운영 부담 | 높음 | 중간 | **낮음** | (Cilium 운영) |
| 사이드카 비용 | 높음 | 낮음(L4) | 낮음 | 없음(L4) |
| mTLS | 설정 필요 | 자동(ztunnel) | **자동** | 투명 암호화 |
| 언제 | 복잡한 요구 | 대규모+비용 | mTLS+메트릭 최소부담 | 이미 Cilium |

★ 판단: 요구 개수 → 기존 스택(Cilium?) → 기능 최대(Istio) vs 운영 최소(Linkerd)
```

## 정리

```bash
bash cleanup.sh
```
