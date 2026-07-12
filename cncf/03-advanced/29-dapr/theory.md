# 이론 — 사이드카 모델, 빌딩블록, 컴포넌트 추상, 메시와의 차이, 판단

> **🌱 17세 눈높이 비유: 만능 개인 비서**
> - **앱** = 바쁜 사장 — 핵심 업무(비즈니스 로직)만 하고 싶습니다
> - **Dapr 사이드카** = 옆자리 만능 비서 — "이거 금고에 넣어줘(상태 저장)", "전 부서에 공지해줘(pub/sub)", "비밀번호 가져와(시크릿)", "옆 팀에 전달해줘(서비스 호출)"를 다 처리
> - **컴포넌트** = 비서의 연락처 — "금고는 Redis 은행", "공지는 Kafka 방송국" — 사장은 은행·방송국이 뭔지 몰라도 됩니다. 비서에게 표준 언어로 시키기만
> - **백엔드 교체** = 은행을 바꿔도 사장의 지시 방식은 그대로 ("이거 금고에 넣어줘")
> - **메시(24·25)와 차이** = 메시는 우편 시스템(네트워크)을 관리하고, Dapr는 사장의 업무(앱 관심사)를 대행합니다 — 다른 층

---

## 1. 사이드카 모델

```
Pod:
  [앱 컨테이너] ──HTTP/gRPC(localhost:3500)──▶ [daprd 사이드카]
                                                   │
                                                   ├─ state store (Redis/DynamoDB...)
                                                   ├─ pub/sub broker (Kafka/NATS...)
                                                   ├─ secret store (Vault/K8s...)
                                                   ├─ service invocation (다른 Dapr 앱)
                                                   └─ bindings (S3/큐/크론...)

컨트롤 플레인 (dapr-system):
  dapr-operator     Component/Configuration CRD 관리
  dapr-sidecar-injector  Pod에 daprd 주입 (annotation)
  dapr-placement    actor 배치 (액터 모델)
  dapr-sentry       mTLS 인증서 (서비스 호출 암호화)

주입: annotation
  dapr.io/enabled: "true"
  dapr.io/app-id: "myapp"
  dapr.io/app-port: "8080"
```

## 2. 빌딩블록 — 표준화된 분산 관심사

| 빌딩블록 | API 예 | 뒤의 구현 | 커리큘럼 |
|---|---|---|---|
| **State** | `PUT /v1.0/state/<store>` | Redis, DynamoDB, Cosmos, Postgres | 09 |
| **Pub/sub** | `POST /v1.0/publish/<broker>/<topic>` | Kafka, RabbitMQ, NATS, Redis | 09 |
| **Service invocation** | `POST /v1.0/invoke/<app>/method/<m>` | 다른 Dapr 앱 (mTLS·재시도·트레이싱) | 24 |
| **Bindings** | 입력(트리거)/출력 | S3, 큐, 크론, HTTP | — |
| **Secrets** | `GET /v1.0/secrets/<store>/<key>` | Vault, K8s Secret, AWS SM | 22 |
| **Actors** | 가상 액터 (상태+동시성) | placement로 배치 | — |
| Configuration, Workflow, Lock, Crypto | — | — | — |

```
공통 패턴:
  앱 → localhost의 표준 API → daprd가 실제 백엔드 처리
  → 앱은 백엔드를 모름, 언어 무관(HTTP), 백엔드 교체는 설정
```

## 3. 컴포넌트 추상 — 이식성의 핵심

```yaml
# State store 컴포넌트 (Redis)
apiVersion: dapr.io/v1alpha1
kind: Component
metadata: { name: statestore }
spec:
  type: state.redis            # ★ 이 type만 바꾸면 백엔드 교체
  version: v1
  metadata:
    - { name: redisHost, value: "redis:6379" }
    - { name: redisPassword, secretKeyRef: { name: redis-secret, key: password } }  # 22
```

```
같은 앱 코드:
  PUT http://localhost:3500/v1.0/state/statestore  [{"key":"x","value":1}]

컴포넌트만 교체:
  state.redis → state.aws.dynamodb → state.azure.cosmosdb → state.postgresql
  → 앱 코드 한 줄도 안 바뀝니다 (05의 CSI, 06의 Collector와 같은 추상)

★ 이식성의 대가·경계:
  각 백엔드의 고유 기능(예: DynamoDB의 특수 쿼리)은 추상에 안 담깁니다
  → "공통 분모"만 이식 가능 (추상의 일반적 한계)
```

## 4. 서비스 호출 — 메시와 겹치는 영역

```
Dapr service invocation:
  POST /v1.0/invoke/order-service/method/checkout
  → daprd가: 서비스 디스커버리 + mTLS(sentry) + 재시도 + 트레이싱(12)
  → 메시(24)의 서비스 간 통신 기능과 겹칩니다!

차이:
  메시: 네트워크 레벨, 앱은 모름(투명), 모든 트래픽
  Dapr: 앱이 Dapr API로 명시적 호출 (앱이 Dapr를 압니다)

공존:
  Dapr(앱 관심사: 상태·pub/sub) + 메시(네트워크: 세밀한 트래픽·전 트래픽 mTLS)
  → 둘 다 사이드카 → 오버헤드 주의, mTLS 이중 등 조정 필요
  → "둘 다 필요한가"를 먼저 (대개 하나로 충분)
```

## 5. 관측·복원력 — 내장

```
관측 (06·12):
  Dapr가 자동으로 트레이스 생성 (service invocation·pub/sub에 span)
  W3C traceparent 전파 (12) — 단 앱 내부 전파는 여전히 앱 책임
  메트릭: dapr_http_server_request_count 등 (11)

복원력 (23의 Envoy 복원력과 같은 계열):
  Resiliency 정책: 재시도(budget), 타임아웃, 서킷 브레이커
  → 빌딩블록 호출에 적용 (state·pubsub·invocation)
  ★ 18의 재시도 규율, 23의 서킷브레이커가 여기서도 (멱등성·budget)
```

## 6. 판단 — Dapr가 맞는가

```
Dapr가 맞는 경우:
  - 다언어 조직 (각 언어로 분산 관심사 재구현이 부담) — Dapr가 언어 무관 표준
  - 백엔드 이식성 중요 (온프레↔클라우드, 벤더 독립)
  - 분산 관심사(상태·pub/sub·시크릿)를 표준화하려는 플랫폼 팀
  - actor 모델이 맞는 도메인 (상태 있는 동시성)

Dapr가 과한 경우:
  - 단일 언어 + 잘 만든 클라이언트 라이브러리로 충분
  - 단순 앱 (사이드카·API 학습 비용 > 이득)
  - 백엔드 하나에 고정 (이식성 불필요)
  - 이미 메시가 서비스 호출을 처리 (invocation 중복)

대가:
  사이드카 오버헤드(메모리·지연·홉), 또 하나의 API·개념, Dapr 의존
  (daprd 문제 = 앱의 상태·pub/sub 중단)
  추상의 공통 분모 한계 (백엔드 고유 기능 접근 어려움)
```

## 7. 소스/도구에서 확인하기

- Dapr: https://docs.dapr.io — building blocks, components, resiliency
- 컴포넌트 목록: https://docs.dapr.io/reference/components-reference/
- Actors: https://docs.dapr.io/developing-applications/building-blocks/actors/
- 08(사다리)·24(메시)·09(pub/sub)·22(시크릿)·12(트레이싱) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| Dapr가 다루는 것? | 앱 관심사(상태·pub/sub·시크릿·호출) — 메시(네트워크)와 다른 층 |
| 사이드카 모델? | 앱 → localhost daprd(표준 API) → 실제 백엔드 |
| 빌딩블록? | State/Pub-sub/Invocation/Bindings/Secrets/Actors — 표준 API |
| 컴포넌트 추상? | type만 바꿔 백엔드 교체 (앱 코드 무수정) — 05의 CSI와 같은 계열 |
| 이식성 한계? | 공통 분모만 — 백엔드 고유 기능은 추상 밖 |
| 메시와 차이? | 앱이 Dapr를 압니다(명시적) vs 메시는 투명. service invocation은 겹침 |
| 복원력? | Resiliency 정책(재시도 budget·타임아웃·서킷) — 18·23의 계열 |
| 언제? | 다언어·이식성·분산 관심사 표준화 / 과함: 단일 언어·단순·백엔드 고정 |
