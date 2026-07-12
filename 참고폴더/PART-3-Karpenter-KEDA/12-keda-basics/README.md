# 12. KEDA Basics — ScaledObject, Scale-to-Zero

## 학습 목표

- HPA 의 한계와 KEDA 가 채워주는 역할 이해
- KEDA 설치 (Helm)
- ScaledObject CRD 로 다양한 트리거 적용 (CPU, Memory, Cron, Prometheus)
- **scale-to-zero** — 사용 없으면 Pod 0 개

## 선행 지식

- 모듈 10~11 완료
- HPA 기본 (Part 1 미니 프로젝트에서 사용했음)

## 진행 순서

1. [theory.md](./theory.md) — KEDA 동작 원리 (15분)
2. [lab-01-install.md](./lab-01-install.md) — Helm 설치 (15분)
3. [lab-02-cpu-scaler.md](./lab-02-cpu-scaler.md) — CPU 트리거 (20분)
4. [lab-03-cron-scaler.md](./lab-03-cron-scaler.md) — Cron + scale-to-zero (20분)
5. [lab-04-prometheus-scaler.md](./lab-04-prometheus-scaler.md) — Prometheus 트리거 (25분)
6. [quiz.md](./quiz.md)
7. [pitfalls.md](./pitfalls.md)

## 다음 모듈

→ [13-keda-event-driven](../13-keda-event-driven/)
