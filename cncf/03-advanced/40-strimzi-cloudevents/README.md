# 40 — Strimzi & CloudEvents: Kafka를 K8s에서, 이벤트를 표준으로

> 09의 데이터 지도에서 두 주민을 함께 다룹니다. **Strimzi**는 Kafka 오퍼레이터(39의 Rook이 Ceph를 운영하듯 Kafka를 운영), **CloudEvents**는 이벤트의 봉투 형식 표준(어떤 브로커든 같은 형식)입니다. 09에서 "Strimzi는 Rook과 동형(시스템 vs 오케스트레이터)", "CloudEvents는 이벤트 표준"이라 소개했습니다. 이 모듈은 Strimzi가 Kafka의 무엇을 자동화하나(39의 오퍼레이터 패턴 반복), CloudEvents가 왜 필요한가(38 NATS·Kafka·클라우드 이벤트를 하나의 형식으로), 그리고 이벤트 기반 아키텍처에서 둘이 어떻게 만나는지를 팝니다. 데이터 트랙(36~40)의 마무리이자 이벤트 표준화의 이야기.

## 학습 목표

1. Strimzi가 Kafka 운영(브로커·토픽·유저·리밸런싱)을 자동화하는 방식을 39와 대비해 압니다
2. Kafka의 K8s 운영 함정(브로커 안티어피니티·PDB·롤링, 09의 그것)을 압니다
3. CloudEvents의 명세(봉투 형식, 컨텍스트 속성)와 왜 이벤트 표준이 필요한지 압니다
4. CloudEvents가 여러 브로커(Kafka·NATS·클라우드)를 통일하는 방식(15의 Knative Eventing과 연결)을 압니다
5. 이벤트 기반 아키텍처에서 Strimzi·CloudEvents·Dapr(29)·KEDA(18)의 조합을 압니다

## 선행: 09(데이터 지도 — 필수), 39(Rook 오퍼레이터 대비), 38(NATS·메시징), 18·29 · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-strimzi-kafka.md](./lab-01-strimzi-kafka.md) — Strimzi 오퍼레이터, Kafka 운영
3. [lab-02-cloudevents-and-architecture.md](./lab-02-cloudevents-and-architecture.md) — CloudEvents 표준, 이벤트 아키텍처
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
