# Lab 02 — 패턴, 클러스터링, 그리고 NATS vs Kafka 선택

18(KEDA)·29(Dapr)와의 연결을 확인하고, NATS의 자리를 Kafka와 대비해 정합니다.

전제: lab-01의 클러스터(kind: nats), JetStream·ORDERS 스트림.

## Step 1. JetStream + KEDA — 18의 연결

```bash
cat <<'EOF'
=== 18의 KEDA JetStream 스케일러 (theory §5) ===
18에서 KEDA로 큐 길이 기반 스케일을 배웠습니다:
  trigger:
    type: nats-jetstream
    metadata:
      stream: ORDERS
      consumer: PROCESSOR
      lagThreshold: "10"     # 미처리 10개당 워커 1개

→ JetStream의 미처리 메시지(pending)로 워커 스케일

★ 18의 규율이 JetStream에서 (theory §5):
  JetStream은 at-least-once → 처리 후 ack 필수
  ack 안 하면 max-deliver 후 재전송 (또는 DLQ)
  워커 SIGTERM 시: 진행 중인 것 ack하고 종료 (graceful)
  → 18의 "오토스케일러가 지키는 것은 replicas이지 메시지가 아니다"
    JetStream의 ack가 메시지를 지킵니다 (core는 못 지킴)
EOF
```

## Step 2. Dapr pub/sub — 29의 연결

```bash
cat <<'EOF'
=== 29의 Dapr pub/sub 백엔드로 NATS (theory §5) ===
29에서 Dapr 컴포넌트로 pub/sub을 배웠습니다:
  apiVersion: dapr.io/v1alpha1
  kind: Component
  metadata: { name: pubsub }
  spec:
    type: pubsub.jetstream    # ★ NATS JetStream을 백엔드로
    metadata:
      - { name: natsURL, value: "nats://nats:4222" }

→ 앱은 Dapr 표준 API로 발행/구독
  POST /v1.0/publish/pubsub/orders
  → Dapr가 NATS JetStream에 (앱은 NATS를 모름)

29의 이식성:
  pubsub.jetstream → pubsub.kafka → pubsub.redis
  → 앱 코드 무관, 컴포넌트 교체 (29의 이식성)
  → NATS가 그 백엔드 중 하나
EOF
```

## Step 3. 클러스터링 — core는 gossip, JetStream은 Raft

```bash
cat <<'EOF'
=== 고가용성 (theory §4, 21) ===
core NATS 클러스터:
  gossip으로 서버 발견, 메시지 라우팅
  저장 없으니 단순 (그냥 메시지 전달)

JetStream 클러스터:
  Raft(21!)로 스트림 복제
  → 영속 데이터라 합의 필요 (etcd·TiKV와 같은 계보)
  → 스트림마다 Raft 그룹 (37의 multi-Raft 계열)
  → 21의 쿼럼(3 복제본 → 2), 리더

★ 21의 Raft가 또 등장:
  etcd(21): 메타데이터
  TiKV(37): 데이터
  JetStream(38): 스트림
  → "영속 상태를 복제하려면 Raft" (분산 시스템 공통)

멀티테넌시 (Account):
  하나의 NATS로 격리된 여러 테넌트 (subject 네임스페이스)
리프 노드:
  엣지에 경량 NATS → 중앙 연결 (02의 엣지)
EOF
```

## Step 4. NATS vs Kafka — 선택

```bash
cat <<'EOF'
=== 선택 (theory §6, 09) ===
| | NATS | Kafka(Strimzi — 40) |
|---|---|---|
| 무게 | 초경량(수 MB) | 무거움(JVM) |
| 지연 | 마이크로초 | 밀리초 |
| 큐 | core 내장 | 컨슈머 그룹 |
| 스트림 | JetStream | 핵심 |
| 생태계 | 성장 | 풍부(Connect·Streams·ksqlDB) |
| 엣지 | 리프 노드(강함) | 무거움 |
| 처리량 | 높음 | 초고(대규모 로그) |

선택:
  가벼운 실시간 + 필요시 스트림 + 엣지·IoT + 마이크로서비스
    → NATS
  대규모 이벤트 로그 + 풍부한 생태계(Connect 커넥터·스트림 처리)
  + 초고처리량 + 기존 Kafka 자산
    → Kafka(40 Strimzi)

★ 09의 판단 + 규모·생태계:
  "나중에 다시 읽어야?"(09) → 스트림이면 JetStream or Kafka
  규모·생태계가 크면 → Kafka
  가볍고 엣지·실시간이면 → NATS
EOF
```

## Step 5. NATS의 독특한 자리

```bash
cat <<'EOF'
=== NATS가 특별한 이유 ===
① 하나의 시스템에 두 모델:
   core(큐) + JetStream(스트림) → 필요에 따라 선택
   (대부분 시스템은 하나만)

② 초경량:
   수 MB 바이너리 → 엣지·IoT·사이드카에 심을 수 있습니다
   (Kafka는 무거워 엣지에 부적합)

③ subject 유연성:
   계층적 subject + 와일드카드 → 유연한 라우팅
   (Kafka 토픽보다 표현력)

④ request-reply:
   메시징 기반 RPC (서비스 통신)
   → 24의 메시 없이도 느슨한 서비스 통신

⑤ 멀티테넌시:
   Account로 격리 → SaaS·멀티테넌트에 적합

→ "가벼움 + 유연함 + 두 모델"이 NATS의 정체성
  25(Linkerd)·27(CRI-O)의 미니멀리즘 계열
EOF
```

## Step 6. 산출물

```markdown
# NATS 종합 카드
## 두 모드
- core(큐·fire-and-forget) + JetStream(스트림·영속)
- 하나의 시스템에 두 모델 (필요시 선택)

## 연결
- 18(KEDA): JetStream 스케일러 + ack 규율
- 29(Dapr): pub/sub 백엔드 (이식성)
- 21(Raft): JetStream 클러스터 복제 (영속 상태)

## 선택 (09 + 규모)
- 가벼운 실시간·엣지·마이크로서비스 → NATS
- 대규모 로그·풍부한 생태계 → Kafka(40)
- "나중에 다시 읽어야?"(09) + 규모·생태계

## 정체성
- 가벼움 + 유연함(subject) + 두 모델 + 멀티테넌시
- 25·27의 미니멀리즘 계열
```

## 정리

```bash
bash cleanup.sh
```
