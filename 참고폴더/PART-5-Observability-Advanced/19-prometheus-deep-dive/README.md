# 19. Prometheus Deep Dive

> **💡 일상 비유로 이해하기**
>
> Prometheus는 본사 직원이 매장마다 정해진 시간(예: 1분)마다 직접 들러서 "오늘 매출 얼마?", "손님 몇 명?"을 묻고 장부에 기록하는 방식과 같습니다. 매장이 직접 본사로 보고하는 게 아니라(push), 본사가 매장을 찾아가는(pull) 구조입니다. 이번 모듈에서는 그 본사의 동선, 장부 보관함(TSDB), 지점망 분리(federation)까지 살펴봅니다.

## 학습 목표

- Prometheus 의 동작 메커니즘 (pull-based scrape, TSDB, retention)
- ServiceMonitor / PodMonitor / Probe CRD 의 역할
- 라벨 (label) 이 cardinality 에 미치는 영향
- federation / remote_write / Thanos sidecar 의 차이

## 선행 지식

- Module 08 (P2) 완료, kube-prometheus-stack 설치되어 있음

## 진행 순서

1. [theory.md](./theory.md) — 아키텍처 (25분)
2. [lab-01-scrape-anatomy.md](./lab-01-scrape-anatomy.md) — scrape 자체 분석 (20분)
3. [lab-02-cardinality.md](./lab-02-cardinality.md) — 라벨 폭발 시연 + 진단 (25분)
4. [lab-03-federation.md](./lab-03-federation.md) — federation 시연 (15분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 다음 모듈

→ [20-promql-mastery](../20-promql-mastery/)
