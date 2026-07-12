# 자가 점검 퀴즈

**Q1.** Strimzi는 무엇이고 39(Rook)와 어떤 점에서 동형인가요?

**Q2.** Strimzi가 관리하는 CR 네 가지와 각 역할은?

**Q3.** `min.insync.replicas`와 복제 팩터·`acks=all`의 관계는? 왜 09의 "가용성 vs 내구성"인가요?

**Q4.** 09의 Kafka 브로커 유지보수 사고를 Strimzi가 어떻게 방지하나요? PDB는 왜 여전히 필요한가?

**Q5.** CloudEvents의 봉투 형식(필수 속성)과 두 바인딩(structured/binary)은?

**Q6.** CloudEvents가 06(OTel)·03(OCI)과 같은 계열이라는 것의 의미는?

**Q7.** 이벤트 기반 아키텍처에서 Kafka/NATS·CloudEvents·Dapr·Knative·KEDA의 층별 역할은?

**Q8.** 이벤트 기반(비동기)과 24(동기 호출)의 차이는? 언제 무엇을 쓰나요?

---

## 정답

**A1.** Strimzi는 Kafka 오퍼레이터 — Kafka 클러스터·토픽·유저·리밸런싱을 K8s CR로 선언형 관리하며 브로커 배포·롤링 업그레이드·재분배를 자동화합니다. 39(Rook)와 동형입니다: 둘 다 08의 오퍼레이터로 복잡한 상태 시스템(Rook→Ceph 스토리지, Strimzi→Kafka 메시징)을 K8s에서 운영하며, "시스템 vs 오케스트레이터"(오퍼레이터는 운영 위임일 뿐 시스템 지식을 없애지 않음), "설치의 쉬움 ≠ 운영의 쉬움", 09의 스테이트풀 판단(관리형 우선)이 그대로 적용됩니다.

**A2.** ① `Kafka`(+`KafkaNodePool`) — 클러스터(브로커·컨트롤러·리스너·스토리지·config), ② `KafkaTopic` — 토픽(파티션·복제·보존), ③ `KafkaUser` — 사용자·권한(ACL·TLS 인증서), ④ `KafkaRebalance`(+Cruise Control) — 파티션 재분배·리밸런싱. 토픽·유저도 CR이므로 GitOps(14·15)로 Git에 커밋해 선언형 관리할 수 있습니다.

**A3.** 복제 팩터는 파티션의 복제본 총수(예: 3), `min.insync.replicas`는 쓰기가 성공하려면 동기화돼 있어야 할 최소 복제본 수(예: 2), `acks=all`은 프로듀서가 min.insync만큼 복제된 뒤에야 ack를 받는 설정입니다. 셋의 조합(복제3+minISR2+acks=all)이면 브로커 하나가 빠져도 쓰기가 되고(가용성) 유실도 막습니다(내구성). minISR을 3으로 높이면 내구성↑·가용성↓(하나만 빠져도 쓰기 정지), 1로 낮추면 가용성↑·내구성↓(하나만 받고 ack → 유실 위험). 그래서 09의 "가용성 vs 내구성" 트레이드오프입니다.

**A4.** Strimzi는 브로커 유지보수를 롤링(한 번에 하나씩, ISR을 확인하며 안전하게)으로 오케스트레이션해 09 사고(노드 드레인이 여러 브로커를 동시 퇴거 → minISR 위반 → 쓰기 실패)를 방지합니다 — 즉 상태 시스템의 유지보수는 K8s 드레인이 아니라 오퍼레이터 절차를 따라야 합니다. 하지만 PDB(PodDisruptionBudget, maxUnavailable:1)는 여전히 필요합니다: 오퍼레이터의 롤링과 무관하게 인프라팀의 **외부 노드 드레인**이 여러 브로커를 동시에 퇴거시키는 것을 막는 것은 PDB이기 때문입니다. 오퍼레이터가 있어도 외부 교란은 PDB가 방어합니다.

**A5.** 봉투 필수 속성: `specversion`, `type`(이벤트 종류, 라우팅 키), `source`(출처 URI), `id`(고유 식별). 선택: `time`, `datacontenttype`, `subject`, `data`(페이로드). 두 바인딩 — structured: 봉투 전체가 JSON body(`Content-Type: application/cloudevents+json`), binary: 컨텍스트 속성이 `ce-*` HTTP 헤더로 가고 `data`만 body. 어느 쪽이든 봉투(specversion·type·source·id)는 항상 같고 data만 앱마다 다릅니다.

**A6.** 셋 다 "표준으로 생태계를 통일해 이식성을 만든다"는 같은 계열입니다 — OTel(06)은 텔레메트리를 시맨틱 컨벤션으로, OCI(03)는 컨테이너 이미지를, CloudEvents는 이벤트를 봉투 형식으로 통일합니다. 결과적으로 소스·백엔드가 바뀌어도 소비자를 안 바꿉니다: S3든 Kafka든 NATS든 이벤트가 CloudEvents 형식이면 소비자는 하나의 코드로 처리합니다. 표준의 가치는 구현이 아니라 **합의된 형식**에 있습니다.

**A7.** 형식(CloudEvents): 이벤트의 공통 봉투. 전송(Kafka 40 / NATS 38): Kafka는 영속 이벤트 로그·대규모, NATS는 경량·실시간·엣지 — 09의 스트림 vs 큐 + 규모로 선택. 추상(Dapr 29): 앱은 pub/sub API만 쓰고 백엔드(Kafka·NATS·Redis)는 교체 가능, 내부적으로 CloudEvents 사용. 라우팅(Knative Eventing): Broker+Trigger로 `type`별 소비자 라우팅. 스케일(KEDA 18): 미처리 이벤트(Kafka consumer lag·NATS pending)를 소스로 소비자를 0→N 오토스케일.

**A8.** 24는 동기 호출(A가 B를 호출하고 응답을 기다림, 강한 결합·즉시성)이고, 이벤트 기반은 비동기(A는 이벤트만 발행하고 잊음, B가 언제 처리하든 무관, 느슨한 결합·확장성)입니다. 즉시 응답·강한 일관성이 필요하면 동기 호출(24, 메시가 안정성 담당), 느슨한 결합·버퍼링·팬아웃·비동기 처리가 필요하면 이벤트 기반을 씁니다. 실무는 둘을 섞되 목적에 맞게 고릅니다 — 이벤트 기반이라면서 즉시 응답을 기다리면(동기를 큐로 흉내) 양쪽 단점만 얻습니다.
