# Lab 02 — mTLS·인가, 그리고 ambient 모드

mTLS가 어디서 종단되는지 확인하고, 인가를 SPIFFE 신원으로 집행한 뒤, ambient 모드가 무엇을 바꾸는지 봅니다.

전제: lab-01의 클러스터(kind: istio), demo 네임스페이스.

## Step 1. mTLS 상태 확인 — 이미 켜져 있습니다

```bash
echo "=== 현재 mTLS 상태 ==="
istioctl proxy-config secret deploy/reviews-v1 -n demo 2>/dev/null | head -5 || \
  kubectl -n demo exec deploy/reviews-v1 -c istio-proxy -- ls /var/run/secrets/workload-spiffe-credentials 2>/dev/null || \
  echo "(사이드카가 istiod CA로부터 인증서를 받습니다)"

echo ""
echo "=== 사이드카가 가진 인증서의 신원 (SPIFFE ID) ==="
istioctl proxy-config secret deploy/reviews-v1 -n demo -o json 2>/dev/null | \
  python3 -c "
import json,sys,base64
try:
    d = json.load(sys.stdin)
    for s in d.get('dynamicActiveSecrets',[]):
        cert = s.get('secret',{}).get('tlsCertificate',{}).get('certificateChain',{}).get('inlineBytes','')
        if cert: print('  인증서 존재 (SPIFFE ID는 SAN에 spiffe://cluster.local/ns/demo/sa/...)')
except: print('  (istioctl proxy-config secret 로 확인)')
" 2>/dev/null || echo "  사이드카 인증서 확인: istioctl proxy-config secret"
```

✅ istiod가 CA로서 각 워크로드에 SPIFFE ID 기반 인증서를 발급했습니다(theory §3, 33에서 심화).

## Step 2. mTLS를 STRICT로 — 그리고 평문 차단 확인

```bash
kubectl -n demo apply -f - <<'EOF'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: { name: default }
spec:
  mtls: { mode: STRICT }        # ★ 사이드카 있는 것끼리만(mTLS), 평문 거부
EOF
sleep 8

echo "=== 메시 안에서 (사이드카 경유) ==="
kubectl -n demo exec client -- curl -s -o /dev/null -w "메시 내부: %{http_code}\n" reviews:9080

echo "=== 메시 밖에서 (사이드카 없는 Pod) ==="
kubectl apply -f - >/dev/null 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: outsider
  namespace: demo
  labels: { run: outsider }
  annotations:
    sidecar.istio.io/inject: "false"    # ← 사이드카 주입 거부 = 메시 밖 신원 없는 클라이언트
spec:
  containers:
    - name: outsider
      image: curlimages/curl
      command: ["sleep", "300"]
EOF
kubectl -n demo wait --for=condition=ready pod/outsider --timeout=60s 2>/dev/null
kubectl -n demo exec outsider -- curl -s -o /dev/null -w "메시 외부: %{http_code}\n" --max-time 5 reviews:9080 2>&1 || echo "메시 외부: 차단됨 ✅ (평문 거부)"
```

예상: 메시 내부 200, 메시 외부 차단. ✅ **STRICT는 사이드카 없는(평문) 통신을 거부**합니다 — 그래서 마이그레이션은 PERMISSIVE부터(theory §3의 audit→enforce 순서).

```bash
cat <<'EOF'
★ 처음부터 STRICT의 위험:
  사이드카가 아직 안 붙은 워크로드(주입 전 Pod, 메시 밖 서비스)와의 통신이 즉시 끊깁니다
  → PERMISSIVE(평문+mTLS 모두 수용)로 시작
  → 전체 워크로드에 사이드카 배포 확인 (istioctl proxy-config로)
  → 그 후 STRICT (07의 audit→enforce, 19의 cert 전파와 같은 이행 곡선)
EOF
```

## Step 3. 인가 — SPIFFE 신원으로 (default-deny)

```bash
kubectl -n demo apply -f - <<'EOF'
# 기본 거부
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: deny-all }
spec: {}                         # 빈 spec = 모두 거부
---
# client의 SA만 reviews에 GET 허용
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: { name: allow-client }
spec:
  selector: { matchLabels: { app: reviews } }
  action: ALLOW
  rules:
    - from: [{ source: { principals: ["cluster.local/ns/demo/sa/default"] } }]
      to: [{ operation: { methods: ["GET"] } }]
EOF
sleep 8

echo "=== GET (허용) ==="
kubectl -n demo exec client -- curl -s -o /dev/null -w "  %{http_code}\n" reviews:9080
echo "=== POST (거부되어야 — GET만 허용) ==="
kubectl -n demo exec client -- curl -s -o /dev/null -w "  %{http_code}\n" -X POST reviews:9080
```

예상: GET 200, POST 403. ✅ **인가는 사이드카의 rbac 필터에서 SPIFFE 신원으로 집행**됩니다(theory §3) — 22의 Cilium L7 정책과 같은 문제(누가 무엇을), 다른 구현(48에서 비교).

## Step 4. 관측 — 사이드카가 만드는 메트릭

```bash
echo "=== istio 메트릭 (사이드카가 자동 생성) ==="
kubectl -n demo exec deploy/reviews-v1 -c istio-proxy -- \
  curl -s localhost:15000/stats/prometheus 2>/dev/null | grep "istio_requests_total" | head -3

cat <<'EOF'
자동 생성 (06의 격자, 12·13과 연결):
  istio_requests_total{source_workload, destination_workload, response_code}  → RED 메트릭
  istio_request_duration_milliseconds_bucket  → p99 (11의 histogram_quantile)
  트레이스: 사이드카가 span 생성 (단 컨텍스트 전파는 앱 책임! — 12)

★ 카디널리티 주의(11·23):
  source × destination × response_code × ... = 시계열 폭발
  메시가 클수록 심각 → 불필요 차원 억제
EOF
```

## Step 5. ambient 모드 — 사이드카를 없앤 세계

```bash
cat <<'EOF'
=== ambient vs 사이드카 (theory §4) ===

[사이드카 모델 — 방금 본 것]
  Pod마다 istio-proxy 컨테이너
  reviews-v1 Pod = [app 컨테이너] + [istio-proxy] ← 메모리·CPU·시작 지연
  → 우리 Pod의 컨테이너가 2개였던 이유

[ambient 모드]
  ztunnel (DaemonSet, 노드당 1): L4 mTLS — 모든 Pod의 트래픽을 노드에서 암호화
    → Pod에 사이드카 없음! (오버헤드 제거)
  waypoint (선택적): L7 (VirtualService·AuthorizationPolicy L7 규칙)
    → L7 기능이 필요한 네임스페이스/서비스에만 배포

계층:
  mTLS만:  app → ztunnel(노드) → ztunnel(노드) → app     (L4, 초경량)
  L7 필요: app → ztunnel → waypoint → ztunnel → app        (선택적 L7)
EOF

# ambient 설치는 별도 프로파일 (개념 확인 — 실제 전환은 신중히)
echo ""
echo "ambient 설치 예: istioctl install --set profile=ambient"
echo "네임스페이스 활성화: kubectl label ns demo istio.io/dataplane-mode=ambient"
echo "→ 사이드카 없이 mTLS가 켜집니다 (ztunnel이 노드에서 처리)"
```

## Step 6. ambient의 의미 — 22의 원칙이 아키텍처로

```bash
cat <<'EOF'
왜 ambient가 중요한가:
  현실: 대부분의 워크로드는 mTLS(L4)만 필요, L7 기능(HTTP 라우팅·인가)은 소수만
  사이드카 모델: 모든 Pod에 full Envoy → L7이 필요 없어도 전부 지불
  ambient: L4는 ztunnel(가벼움) + L7은 waypoint(필요한 곳만)
  → 22(Cilium)에서 배운 "L7은 필요한 곳에만"을 메시 아키텍처에 새긴 것

트레이드오프:
  ✅ 비용↓ (대부분 L4만), 업그레이드 용이(전 Pod 재시작 없음)
  ⚠️ 상대적으로 새로움(성숙도·엣지 케이스), 트래픽 경로 변화(디버깅 모델),
     ztunnel의 노드 단위 장애 반경

판단: 메시를 도입한다면 ambient를 진지하게 검토 (특히 mTLS가 주 요구일 때)
      단 성숙도·운영 경험을 채택 전에 확인 (01의 소견서)
EOF
```

## Step 7. 산출물 — 메시 판단 카드

```markdown
# Istio 보안·ambient 카드
## 보안
- mTLS: 사이드카(또는 ztunnel)가 종단, SPIFFE ID 기반 (33)
- 마이그레이션: PERMISSIVE → 배포 확인 → STRICT (07의 audit→enforce)
- 인가: AuthorizationPolicy, rbac 필터에서 SPIFFE 신원으로 (22와 같은 문제)
- ★ 인증서 만료 = 통신 두절 (19의 교훈이 메시에서 치명적)

## ambient
- ztunnel(L4 mTLS, 노드당) + waypoint(L7, 선택) — 사이드카 제거
- "L7은 필요한 곳에만"(22)을 아키텍처에
- 비용↓·업그레이드 용이 / 성숙도·경로 변화·노드 장애 반경

## 도입 판단
- mTLS·트래픽관리·관측 중 몇 개가 실제 요구인가요?
- 1개면 가벼운 대안(Cilium 암호화, Argo Rollouts+Gateway API)
- 3개 겹치고 운영 역량 있으면 메시 (ambient가 저울을 조금 옮김)
```

## 정리

```bash
bash cleanup.sh
```
