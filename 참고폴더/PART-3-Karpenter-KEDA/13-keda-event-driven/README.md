# 13. KEDA Event-Driven — SQS + Kafka 트리거

## 학습 목표

- AWS SQS 큐 길이 기반 ScaledObject (with IRSA)
- Kafka topic lag 기반 ScaledObject
- Module 09 의 payment-service / notification-service 를 실제로 동작시킴

## 선행 지식

- 모듈 12 완료 (KEDA 작동)
- 모듈 09 의 MSA 가 떠 있음

## 진행 순서

1. [theory.md](./theory.md) — SQS / Kafka scaler 동작 + IRSA (15분)
2. [lab-01-sqs.md](./lab-01-sqs.md) — SQS 큐 + payment-service ScaledObject (35분)
3. [lab-02-kafka.md](./lab-02-kafka.md) — In-cluster Kafka + notification-service ScaledObject (40분)
4. [quiz.md](./quiz.md)
5. [pitfalls.md](./pitfalls.md)

## 다음 모듈

→ [14-karpenter-keda-combo](../14-karpenter-keda-combo/) — **시나리오의 절정**
