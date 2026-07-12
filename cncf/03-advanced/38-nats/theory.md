# 이론 — core NATS, subject, request-reply, JetStream, 클러스터링, 선택

> **🌱 17세 눈높이 비유: 교내 방송과 녹음실**
> - **core NATS(방송)** = 실시간 교내 방송 — 지금 듣는 사람만 듣습니다. 안 듣고 있었으면 놓칩니다(fire-and-forget)
>   - **subject** = 방송 채널 ("급식.메뉴", "동아리.*") — 계층적 주제
>   - **큐 그룹** = 여러 방송부원이 있는데 한 명만 응답 (작업 분배)
>   - **request-reply** = "질문 방송하면 답장 방송" (양방향)
> - **JetStream(녹음실)** = 방송을 녹음해 저장 — 나중에 재생, 여러 번 들을 수 있습니다(영속 스트림)
> - **하나의 시스템** = 같은 방송 장비로 실시간 방송(core)도 녹음(JetStream)도
> - **선택** = "지금 안 들으면 그만"이면 방송(core), "나중에 다시 들어야"면 녹음(JetStream) — 09의 판단

---

## 1. core NATS — 초경량 pub/sub

```
특징:
  수 MB 바이너리, 마이크로초 지연
  fire-and-forget: 발행 시 구독자에게 전달, 저장 안 함
  구독자 없으면 메시지 유실 (at-most-once)

subject 기반:
  발행: PUB orders.new {...}
  구독: SUB orders.new  또는  SUB orders.*  (와일드카드)
  계층: orders.new, orders.paid, orders.* (한 단계), orders.> (모든 하위)
  → 토픽이 아니라 계층적 subject (라우팅 유연)

전달 모델:
  일반 pub/sub: 모든 구독자가 받음 (팬아웃)
  큐 그룹: 같은 그룹의 구독자 중 하나만 받음 (로드밸런싱)
    SUB orders.new WORKERS  → WORKERS 그룹의 한 워커만
    → 작업 분배 (여러 워커가 나눠 처리)
```

## 2. request-reply — 양방향

```
NATS의 독특한 패턴: 요청-응답을 pub/sub으로
  요청자: PUB service.method reply-to=INBOX.xyz {...}
  응답자: SUB service.method → 처리 → PUB INBOX.xyz {result}
  → 임시 reply subject로 응답 받음

용도:
  마이크로서비스 간 동기 호출 (24의 메시 service invocation과 유사)
  하지만 메시징 기반 (느슨한 결합)
  스케일: 여러 응답자를 큐 그룹으로 → 로드밸런싱된 RPC
```

## 3. JetStream — 영속 스트림

```
core 위의 영속성 계층:
  Stream: subject의 메시지를 로그에 저장
    orders.* 를 EVENTS 스트림에 저장 (파일/메모리)
    보존: 크기·개수·시간·interest 기반
  Consumer: 스트림에서 메시지를 읽는 방법
    push/pull, 위치(처음/마지막/특정 시퀀스)
    ack: 처리 확인 (at-least-once)

Kafka와 유사:
  Stream ≈ Kafka 토픽 (영속 로그)
  Consumer ≈ Kafka 컨슈머 그룹
  재생: 과거 메시지 다시 읽기 (09의 스트림 특성)

core와 차이:
  core: 구독자 없으면 유실, 저장 안 함
  JetStream: 저장, 나중에 재생, at-least-once
  → 09의 "나중에 다시 읽어야 하는가"의 답
```

## 4. 클러스터링 — 고가용성

```
core NATS 클러스터:
  gossip 프로토콜로 서버들이 서로 발견
  풀 메시 또는 슈퍼클러스터(지역 간)
  → 메시지 라우팅 (저장 없으니 단순)

JetStream 클러스터:
  Raft(21!)로 스트림 복제 (영속 데이터라 합의 필요)
  → 스트림마다 Raft 그룹 (37의 multi-Raft와 유사 계열)
  → 21의 쿼럼·리더가 여기서도

멀티테넌시:
  Account: 격리된 테넌트 (subject 네임스페이스 분리)
  → 하나의 NATS로 여러 테넌트 (16의 멀티테넌시와 계열)

리프 노드(leaf node):
  엣지에 경량 NATS → 중앙과 연결 (엣지·IoT)
  → 02의 KubeEdge와 같은 엣지 문제의식
```

## 5. 09·18·29와의 연결

```
09(큐 vs 스트림):
  core = 큐(fire-and-forget), JetStream = 스트림(영속)
  판단: "나중에 다시 읽어야 하는가"

18(KEDA 스케일러):
  JetStream 스케일러 → 미처리 메시지 수로 워커 스케일
  ★ 18의 SIGTERM·ack 규율이 여기서:
    JetStream은 at-least-once → ack 안 하면 재전송
    워커가 처리 후 ack (graceful shutdown 시 진행 중인 것 마무리)

29(Dapr pub/sub):
  Dapr 컴포넌트로 NATS → 앱이 표준 API로 발행/구독
  → NATS가 Dapr의 pub/sub 백엔드 (이식성)
```

## 6. 선택 — NATS vs Kafka

| | NATS | Kafka |
|---|---|---|
| 무게 | 초경량(수 MB) | 무거움(JVM·ZK/KRaft) |
| 지연 | 마이크로초 | 밀리초 |
| 큐 | core(내장) | (컨슈머 그룹) |
| 스트림 | JetStream | 핵심 |
| 생태계 | 성장 | 풍부(Connect·Streams) |
| 엣지 | 리프 노드(강함) | 무거움 |
| 처리량 | 높음 | 초고(대규모 로그) |
| 자리 | 실시간·엣지·마이크로서비스 | 대규모 이벤트 로그 |

```
선택:
  가벼운 실시간 + 필요시 스트림 + 엣지 → NATS
  대규모 이벤트 로그 + 풍부한 생태계(Connect) → Kafka(Strimzi — 40)
  → 09의 판단(큐 vs 스트림) + 규모·생태계
```

## 7. 소스/도구에서 확인하기

- NATS: https://docs.nats.io — core, JetStream, clustering
- JetStream: https://docs.nats.io/nats-concepts/jetstream
- 09(데이터)·18(KEDA)·29(Dapr)·40(Strimzi/Kafka)·21(Raft) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| 두 얼굴? | core(큐·fire-and-forget) / JetStream(스트림·영속) — 하나의 서버에 |
| subject? | 계층적 주제(orders.*) — 토픽보다 유연한 라우팅 |
| 큐 그룹? | 같은 그룹 중 하나만 받음 (로드밸런싱·작업 분배) |
| request-reply? | pub/sub 기반 양방향 — 메시징 RPC |
| JetStream? | 영속 스트림(Kafka 유사) — 저장·재생·at-least-once |
| 클러스터링? | core는 gossip, JetStream은 Raft(21 — 영속이라 합의) |
| 18·29 연결? | KEDA 스케일러(ack 규율), Dapr pub/sub 백엔드 |
| NATS vs Kafka? | 초경량·엣지·실시간 vs 대규모 로그·생태계 |
