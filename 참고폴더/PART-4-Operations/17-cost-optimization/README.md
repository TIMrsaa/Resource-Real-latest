# 17. Cost Optimization

## 학습 목표

EKS 비용을 가시화하고, 우상향하는 비용의 원인을 정확히 진단해 줄이는 방법.

- AWS Cost Explorer 활용
- Container Insights 의 사용률 분석
- KubeCost / OpenCost 로 NS / Pod 단위 비용 배분
- Karpenter Consolidation + Spot 최적화
- VPA 로 자동 right-sizing

## 선행 지식

- Part 3 완료 (Karpenter / KEDA 동작 이해)
- 클러스터 + Container Insights 또는 Prometheus

## 진행 순서

1. [theory.md](./theory.md) — 비용 모델 + 우상향 진단 (15분)
2. [lab-01-cost-explorer.md](./lab-01-cost-explorer.md) — AWS 비용 분석 (20분)
3. [lab-02-rightsizing.md](./lab-02-rightsizing.md) — Container Insights + VPA (30분)
4. [lab-03-opencost.md](./lab-03-opencost.md) — OpenCost 설치 + NS 비용 배분 (25분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 비용

학습 자체 비용 < 1 USD. OpenCost / VPA 는 Helm 으로 가볍게 설치.

## 다음 모듈

→ [18-upgrade-strategy](../18-upgrade-strategy/)
