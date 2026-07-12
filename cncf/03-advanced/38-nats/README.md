# 38 — NATS 심층: 하나의 도구, 두 얼굴(큐와 스트림)

> 09의 데이터 지도에서 이미 만난, "core는 큐, JetStream은 스트림"이라 소개한 그 흥미로운 프로젝트. 대부분의 메시징 시스템이 큐(RabbitMQ)이거나 스트림(Kafka)인데, NATS는 하나의 시스템에서 둘 다 합니다 — core NATS(초경량 pub/sub·fire-and-forget)와 JetStream(영속 스트림). 이 모듈은 그 두 모드의 실체, 언제 무엇을 쓰나, 그리고 09에서 배운 "큐 vs 스트림" 판단과 18(KEDA)의 스케일러·29(Dapr)의 pub/sub이 NATS와 어떻게 연결되는지를 팝니다. 09 lab-02에서 core와 JetStream을 만졌다면, 여기서 그 구조를 깊게 봅니다.

## 학습 목표

1. core NATS(pub/sub·request-reply)와 JetStream(스트림)의 아키텍처 차이를 압니다
2. subject 기반 메시징과 큐 그룹(로드밸런싱), request-reply 패턴을 이해합니다
3. JetStream의 스트림·컨슈머 모델과 영속성·재생을 압니다
4. NATS의 클러스터링(gossip·raft)과 09의 큐 vs 스트림 판단을 연결합니다
5. NATS의 자리(초경량·엣지·IoT) vs Kafka(대규모 로그)의 선택을 압니다

## 선행: 09(데이터 지도·큐 vs 스트림 — 필수), 18(KEDA 스케일러), 29(Dapr pub/sub), 21(Raft) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-core-and-jetstream.md](./lab-01-core-and-jetstream.md) — 두 모드, subject·큐그룹·스트림
3. [lab-02-patterns-and-choice.md](./lab-02-patterns-and-choice.md) — 패턴·클러스터링·선택
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
