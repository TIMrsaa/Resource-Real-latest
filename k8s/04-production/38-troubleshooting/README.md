# 38 — 트러블슈팅: 장애 시나리오 10선

> 지금까지 모듈마다 흩어져 있던 "장애의 조각들"을 하나의 **진단 체계**로 묶습니다. 대표 장애 10가지를 직접 일으키고, 표준 루틴으로 잡습니다 — 이 모듈의 산출물은 새벽 3시의 나를 구할 진단 카드입니다.

## 학습 목표

1. 표준 진단 루틴(증상 → 계층 → describe/events/logs → 원인)을 몸에 붙입니다
2. 워크로드 장애 5선을 재현하고 진단합니다 (CrashLoop, ImagePull, OOM, Pending, Probe)
3. 연결 장애 5선을 재현하고 진단합니다 (DNS, Service 불일치, NetworkPolicy, PVC, 노드)
4. "증상 → 1순위 의심 → 확인 명령" 진단 카드를 완성합니다

## 선행: 초/중급 전체 (특히 03, 05, 14, 16) — 이 모듈은 종합 시험장 · 환경: 공유 EKS

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-workload-failures.md](./lab-01-workload-failures.md) — 워크로드 장애 5선
3. [lab-02-connectivity-failures.md](./lab-02-connectivity-failures.md) — 연결/플랫폼 장애 5선
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h
