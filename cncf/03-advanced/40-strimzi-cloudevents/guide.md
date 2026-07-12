# 학습 가이드 — 시스템 운영과 형식 표준

## 두 프로젝트, 두 층

이 모듈은 이벤트/메시징의 두 다른 층을 다룹니다:

```
Strimzi: Kafka(시스템)를 K8s에서 운영 (인프라 층)
CloudEvents: 이벤트의 형식 표준 (데이터 형식 층)
```

Strimzi는 39(Rook)와 같은 이야기입니다 — 복잡한 시스템(Kafka)을 오퍼레이터로 K8s에서 운영합니다. CloudEvents는 완전히 다른 종류입니다 — 코드가 아니라 **명세**(이벤트가 어떻게 생겨야 하나)이고, 06(OTel)·03(OCI)처럼 표준으로 생태계를 통일합니다.

## Strimzi — 39의 반복

39에서 "Rook은 Ceph 오퍼레이터"를 배웠습니다. Strimzi는 정확히 같은 패턴의 Kafka판입니다:

```
Rook: Ceph를 운영 (스토리지 시스템)
Strimzi: Kafka를 운영 (메시징 시스템)
공통: 08의 오퍼레이터 = 운영 지식의 코드화
     "시스템 vs 오케스트레이터" (09·05)
     "설치의 쉬움 ≠ 운영의 쉬움"
     09의 스테이트풀 판단
```

09에서 배운 Kafka의 K8s 함정(브로커 드레인 = 데이터 위험, 안티어피니티, PDB, ISR)이 여기서 Strimzi가 어떻게 다루는지로 이어집니다. 09 사고 사례(Kafka 브로커를 노드 드레인으로 그냥 퇴거 → 파티션 손상)가 Strimzi의 롤링 업데이트(ISR을 보며 안전하게)로 방지되는 것을 봅니다.

## CloudEvents — 표준의 가치

06(OTel)에서 "표준의 가치는 이식성"을 배웠습니다. CloudEvents는 이벤트에서 같은 일을 합니다:

```
표준 없이: AWS EventBridge 이벤트, Kafka 메시지, NATS 메시지가
          각각 다른 형식 → 이벤트 소스마다 다른 파싱
CloudEvents: 이벤트의 봉투를 표준화
  { specversion, type, source, id, time, data }
  → 어떤 브로커·소스든 같은 형식 → 통일된 처리
```

38에서 배운 NATS, 09의 Kafka, 클라우드 이벤트(S3 알림 등)가 전부 CloudEvents 형식으로 표현될 수 있습니다 — 12(OTel)의 시맨틱 컨벤션이 텔레메트리를 통일했듯, CloudEvents가 이벤트를 통일합니다.

## 15와의 연결 — Knative Eventing

15(Flux)에서, 그리고 08의 5단(Knative)에서 이벤트 라우팅을 스쳤습니다. Knative Eventing이 CloudEvents 기반입니다 — 이벤트를 CloudEvents로 표준화하고 브로커·트리거로 라우팅합니다. 이 모듈은 그 표준(CloudEvents)의 실체를 봄으로써 이벤트 기반 아키텍처의 기반을 완성합니다.

## 이벤트 기반 아키텍처의 조합

데이터 트랙의 여러 조각이 이벤트 아키텍처에서 만납니다:

```
Strimzi/Kafka(40): 이벤트 로그 (영속)
NATS(38): 경량 이벤트/메시징
CloudEvents(40): 이벤트 형식 표준
Dapr(29): pub/sub 추상 (CloudEvents 사용)
KEDA(18): 이벤트로 워커 스케일
→ 이벤트 기반 시스템의 부품들
```
