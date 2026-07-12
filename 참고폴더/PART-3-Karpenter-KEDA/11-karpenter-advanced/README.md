# 11. Karpenter Advanced — Spot, Disruption, 비용 최적화

## 학습 목표

- 다중 인스턴스 패밀리 + 다중 AZ 로 Spot 안정성 확보
- Disruption 정책 (Drift, Expiration, Spot Interruption) 동작
- On-Demand fallback (Spot 부족 시 자동 전환)
- 두 NodePool 분리 (workload-tier 별)
- 비용 비교: 학습 전후 Cost Explorer

## 선행 지식

- 모듈 10 완료, Karpenter 작동 중

## 진행 순서

1. [theory.md](./theory.md) — Disruption 깊이 + Spot 전략 (20분)
2. [lab-01-spot-diversity.md](./lab-01-spot-diversity.md) — 다중 family/AZ (25분)
3. [lab-02-disruption.md](./lab-02-disruption.md) — Drift, Expiration (25분)
4. [lab-03-cost-explorer.md](./lab-03-cost-explorer.md) — 비용 비교 (15분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 다음 모듈

→ [12-keda-basics](../12-keda-basics/)
