# 자가 점검 퀴즈

**Q1.** core NATS와 JetStream의 차이는? "NATS vs Kafka"가 09에서 왜 모드를 밝혀야 성립하나요?

**Q2.** subject 기반 메시징이 토픽보다 유연한 점은? 큐 그룹은 무엇을 하나요?

**Q3.** request-reply 패턴은 어떻게 동작하나요? 24의 무엇과 유사한가?

**Q4.** JetStream의 Stream과 Consumer는 Kafka의 무엇에 대응하나요? core와의 결정적 차이는?

**Q5.** core NATS와 JetStream의 클러스터링 차이는? 21의 무엇이 재등장하나요?

**Q6.** 18(KEDA)과 29(Dapr)에서 NATS가 어떻게 쓰이나요? 18의 ack 규율은?

**Q7.** NATS vs Kafka 선택 기준은? 각각이 빛나는 곳은?

**Q8.** NATS의 독특한 정체성 다섯 가지는? 어느 모듈들의 미니멀리즘 계열인가요?

---

## 정답

**A1.** core NATS는 초경량 pub/sub로 fire-and-forget(발행 시 구독자에게 전달하고 저장 안 함, 구독자 없으면 유실, at-most-once)이고, JetStream은 core 위의 영속성 계층으로 메시지를 로그에 저장해 재생 가능하고 at-least-once입니다. "NATS vs Kafka"가 모드를 밝혀야 하는 이유: core NATS는 큐(Kafka의 스트림과 다른 층)이고 JetStream은 스트림(Kafka와 같은 층)이라 — "NATS"라고만 하면 큐(core)와 스트림(JetStream) 중 무엇을 말하는지 알 수 없습니다(09의 큐 vs 스트림 판단).

**A2.** subject는 계층적 주제(orders.new, orders.paid)에 와일드카드(orders.* = 한 단계, orders.> = 모든 하위)를 쓸 수 있어, 고정된 토픽보다 유연한 라우팅이 가능합니다 — 하나의 구독으로 여러 관련 subject를 받거나 세밀하게 필터링합니다. 큐 그룹: 같은 큐 그룹에 속한 구독자들 중 하나만 각 메시지를 받습니다(로드밸런싱·작업 분배) — 일반 pub/sub이 모든 구독자에게 팬아웃하는 것과 달리, 큐 그룹은 여러 워커가 메시지를 나눠 처리하게 합니다.

**A3.** 요청자가 임시 reply subject(INBOX.xyz)를 지정해 메시지를 발행하면, 응답자가 그 subject를 구독해 처리 후 reply subject로 응답을 발행합니다 — pub/sub 기반의 양방향 통신입니다. 24(Istio)의 service invocation(서비스 간 호출)과 유사하지만 메시징 기반이라 더 느슨한 결합이며, 응답자를 큐 그룹으로 두면 로드밸런싱된 RPC가 됩니다. 메시징 시스템으로 동기 요청-응답을 구현하는 NATS의 독특한 패턴입니다.

**A4.** Stream은 Kafka 토픽(subject의 메시지를 저장하는 영속 로그)에, Consumer는 Kafka 컨슈머 그룹(스트림에서 읽는 방법 — push/pull, 위치, ack)에 대응합니다. core와의 결정적 차이: core는 저장하지 않아 구독자가 없으면 유실되지만(at-most-once), JetStream은 메시지를 저장해 나중에 재생 가능하고 ack 기반 at-least-once를 제공합니다 — 09의 "나중에 다시 읽어야 하는가"의 답이 JetStream입니다.

**A5.** core NATS 클러스터는 gossip 프로토콜로 서버를 발견하고 메시지를 라우팅합니다(저장이 없으니 단순). JetStream 클러스터는 Raft(21)로 스트림을 복제합니다 — 영속 데이터라 합의가 필요하기 때문입니다. 21의 Raft가 재등장: etcd(메타데이터), TiKV(37 — 데이터), JetStream(38 — 스트림)에서 모두 Raft로 영속 상태를 복제합니다("영속 상태를 복제하려면 Raft"가 분산 시스템의 공통 원리). 스트림마다 Raft 그룹이고 쿼럼(3 복제본 → 2)·리더가 21과 동일합니다.

**A6.** 18(KEDA): NATS JetStream 스케일러가 스트림의 미처리 메시지(lag)로 처리 워커를 스케일합니다. 29(Dapr): pubsub.jetstream 컴포넌트로 NATS를 pub/sub 백엔드로 써서 앱이 표준 API로 발행/구독하고 백엔드 교체가 컴포넌트 설정이 됩니다(이식성). 18의 ack 규율: JetStream은 at-least-once라 워커가 메시지를 처리한 뒤 명시적으로 ack해야 하고(auto-ack 금지), ack 안 하면 재전송되며, SIGTERM 시 진행 중인 메시지를 마무리한 뒤 종료해야 합니다 — "오토스케일러가 지키는 것은 replicas이지 메시지가 아니며, JetStream의 ack가 메시지를 지킨다".

**A7.** NATS: 초경량(수 MB), 마이크로초 지연, core 내장 큐, JetStream 스트림, 엣지 리프 노드가 강함, 멀티테넌시(Account) — 가벼운 실시간 통신·엣지/IoT·마이크로서비스에 빛납니다. Kafka(40 Strimzi): 무겁지만(JVM) 풍부한 생태계(Connect의 수백 커넥터, Streams·ksqlDB), 초고처리량 — 대규모 이벤트 로그·풍부한 스트림 처리·기존 Kafka 자산에 빛납니다. 선택: 09의 판단(큐 vs 스트림) + 규모·생태계 — 가벼운 실시간·엣지면 NATS, 대규모 로그·생태계면 Kafka, 둘을 함께 쓰기도(엣지 NATS + 중앙 Kafka).

**A8.** ① 하나의 시스템에 두 모델(core 큐 + JetStream 스트림 — 필요에 따라 선택). ② 초경량(수 MB 바이너리 → 엣지·IoT·사이드카에 심을 수 있음). ③ subject 유연성(계층적 + 와일드카드 → 유연한 라우팅). ④ request-reply(메시징 기반 RPC → 메시 없이 느슨한 서비스 통신). ⑤ 멀티테넌시(Account 격리 → SaaS·멀티테넌트). 25(Linkerd — 단순함도 설계), 27(CRI-O — 미니멀리즘)과 같은 계열로, "가벼움 + 유연함 + 두 모델"이 NATS의 정체성이며 Kafka의 "처음부터 무거운 대규모 로그"와 대비됩니다.
