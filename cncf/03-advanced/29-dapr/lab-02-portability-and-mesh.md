# Lab 02 — 백엔드 교체(이식성)와 메시와의 차이·공존

컴포넌트만 바꿔 백엔드를 교체하는 것을 확인하고, Dapr가 메시(24·25)와 어떻게 다르고 언제 공존하는지 정리합니다.

전제: lab-01의 클러스터(kind: dapr), app·statestore.

## Step 1. 이식성 실증 — 앱 코드는 그대로, 백엔드만 교체

```bash
POD=$(kubectl get pod -l app=app -o name | head -1)

echo "=== 현재: Redis 백엔드에 저장된 상태 ==="
kubectl exec $POD -c app -- curl -s http://localhost:3500/v1.0/state/statestore/order-1
echo ""

# In-memory 백엔드로 교체 (실제로는 DynamoDB·Cosmos 등)
echo "=== statestore 컴포넌트를 in-memory로 교체 ==="
kubectl apply -f - <<'EOF'
apiVersion: dapr.io/v1alpha1
kind: Component
metadata: { name: statestore }
spec:
  type: state.in-memory        # ★ redis → in-memory (앱 코드 무관)
  version: v1
EOF
# 사이드카가 컴포넌트 변경을 반영하려면 앱 재시작
kubectl rollout restart deploy/app
kubectl rollout status deploy/app --timeout=120s
POD=$(kubectl get pod -l app=app -o name | head -1)
sleep 5

echo "=== 같은 API로 저장·조회 (백엔드는 이제 in-memory) ==="
kubectl exec $POD -c app -- curl -s -X POST http://localhost:3500/v1.0/state/statestore \
  -H "Content-Type: application/json" -d '[{"key":"order-2","value":{"item":"pen"}}]'
kubectl exec $POD -c app -- curl -s http://localhost:3500/v1.0/state/statestore/order-2
echo ""
echo "→ 앱 코드는 한 줄도 안 바뀌었습니다. type만 state.redis → state.in-memory"
```

✅ **컴포넌트 추상의 이식성**(theory §3) — 05의 CSI(스토리지), 06의 Collector(관측)가 한 것을 앱 관심사에서. 온프레(Redis)↔클라우드(DynamoDB) 이전이 컴포넌트 교체가 됩니다.

## Step 2. 이식성의 한계 — 공통 분모만

```bash
cat <<'EOF'
=== 추상의 일반적 한계 (theory §3) ===
이식 가능: 공통 분모 (get/set/delete, TTL, 기본 트랜잭션)
이식 불가: 백엔드 고유 기능
  - DynamoDB의 GSI 쿼리
  - Redis의 특수 자료구조(sorted set 연산)
  - Cosmos의 지리 분산 설정

→ Dapr로 이식성을 얻는 대신 백엔드의 강력한 고유 기능은 포기
→ "공통 분모로 충분한가"가 판단 기준
  (05의 CSI가 스토리지 고유 기능을 다 노출 못 하는 것과 같은 트레이드오프)
EOF
```

## Step 3. 서비스 호출 — 메시와 겹치는 지점

```bash
echo "=== Dapr service invocation ==="
kubectl exec $POD -c app -- curl -s \
  http://localhost:3500/v1.0/invoke/subscriber/method/anything 2>/dev/null | head -1 || \
  echo "(subscriber 앱을 Dapr로 호출 — mTLS·재시도·트레이싱 내장)"

cat <<'EOF'

Dapr service invocation이 하는 것 (theory §4):
  서비스 디스커버리(app-id로) + mTLS(sentry) + 재시도 + 트레이싱(12)
  → 메시(24)의 서비스 간 통신 기능과 겹칩니다!

차이:
  메시(24·25): 네트워크 레벨, 앱은 모름(투명), 모든 트래픽에 적용
  Dapr:        앱이 명시적으로 Dapr API 호출 (앱이 Dapr를 압니다)
             → 앱 관심사(상태·pub/sub)와 함께 제공
EOF
```

## Step 4. 메시와 Dapr — 다른 층, 겹치는 영역

```bash
cat <<'EOF'
=== Dapr vs 메시 (theory §4) ===
| | Dapr | 서비스 메시(24·25) |
|---|---|---|
| 다루는 것 | 앱 관심사(상태·pub/sub·시크릿·호출) | 네트워크(트래픽·mTLS·관측) |
| 앱의 인지 | 명시적(Dapr API 호출) | 투명(앱 무관) |
| 적용 범위 | Dapr API를 쓰는 곳 | 모든 트래픽 |
| 겹침 | service invocation(mTLS·재시도) | 서비스 간 통신 |

공존:
  Dapr(상태·pub/sub) + 메시(전 트래픽 mTLS·세밀 라우팅)
  → 둘 다 사이드카 → Pod에 사이드카 2개(+앱) → 오버헤드
  → mTLS 이중 등 조정 필요 (Dapr sentry + 메시 CA)
  ★ 대개 하나로 충분 — "둘 다 정말 필요한가"를 먼저

선택 감각:
  앱 관심사(상태·pub/sub) 표준화가 주 목적 → Dapr
  네트워크 제어(트래픽·전 트래픽 mTLS·관측) 주 목적 → 메시
  service invocation만 필요 → 둘 중 하나로 (중복 회피)
EOF
```

## Step 5. 복원력 정책 — 18·23의 계열

```bash
kubectl apply -f - <<'EOF'
apiVersion: dapr.io/v1alpha1
kind: Resiliency
metadata: { name: myapp-resiliency }
spec:
  policies:
    retries:
      retryForever:
        policy: exponential
        maxRetries: 3
    circuitBreakers:
      simpleCB:
        maxRequests: 1
        interval: 30s
        timeout: 60s
        trip: consecutiveFailures >= 5
  targets:
    apps:
      subscriber:
        retry: retryForever
        circuitBreaker: simpleCB
EOF

cat <<'EOF'
Dapr Resiliency (theory §5):
  재시도(budget), 타임아웃, 서킷 브레이커 → 빌딩블록 호출에 적용
  = 23의 Envoy 복원력, 18의 재시도 규율이 앱 관심사 레벨에서

★ 같은 규율 반복:
  재시도는 멱등 요청에 + budget으로 폭풍 방지 (18·23)
  서킷 브레이커로 빠른 실패 (23)
EOF
```

## Step 6. 판단 — Dapr가 맞는가

```bash
cat <<'EOF'
=== 결정 트리 (theory §6) ===

분산 관심사(상태·pub/sub·시크릿)를 표준화하고 싶은가요?
  ↓ Yes
다언어 조직인가요? (각 언어로 재구현이 부담)
  Yes → Dapr가 강점 (언어 무관 표준 API)
백엔드 이식성이 중요한가? (온프레↔클라우드, 벤더 독립)
  Yes → Dapr의 컴포넌트 추상
actor 모델이 도메인에 맞나요?
  Yes → Dapr actors

Dapr가 과한 경우:
  단일 언어 + 좋은 클라이언트 라이브러리 → 라이브러리로 충분
  단순 앱 → 사이드카·API 학습 비용 > 이득
  백엔드 고정 → 이식성 불필요
  이미 메시가 service invocation 처리 → 중복

대가:
  사이드카 오버헤드, 또 하나의 API, Dapr 의존(daprd 죽으면 상태·pubsub 중단)
  공통 분모 한계(백엔드 고유 기능)
EOF
```

## Step 7. 산출물 — 08의 5단 종합

```markdown
# Dapr 판단 카드
## 정체 (08의 5단)
- "앱 코드 위의 추상" — 분산 관심사(상태·pub/sub·시크릿·호출)를 사이드카 API로
- 메시(네트워크)와 다른 층, service invocation만 겹침

## 언제
- 다언어 조직 (언어 무관 표준)
- 백엔드 이식성 (컴포넌트 교체)
- 분산 관심사 표준화 (플랫폼 팀)
- actor 모델 도메인

## 언제 아닌가
- 단일 언어 + 좋은 라이브러리
- 단순 앱, 백엔드 고정
- 메시가 이미 service invocation 처리

## 반복된 규율
- 이식성 vs 고유기능 (05의 CSI 트레이드오프)
- 재시도 budget·서킷 브레이커 (18·23)
- 사이드카 오버헤드 (24의 메시 비용)
```

## 정리

```bash
bash cleanup.sh
```
