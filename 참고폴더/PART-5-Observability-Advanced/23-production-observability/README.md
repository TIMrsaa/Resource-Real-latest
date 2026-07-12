# 23. Production Observability

## 학습 목표

운영 수준의 관측 스택 — HA, 장기 저장, SLO/SLI, alert 라우팅.

- Prometheus HA (다중 replicas) + 중복 메트릭 처리
- 장기 저장 옵션: Thanos / Mimir / AWS Managed Prometheus
- SLI / SLO / Error Budget — multi-window/multi-burn-rate alerting
- Alertmanager 라우팅 + 억제(inhibition) + 묵음(silence)
- Runbook annotation 패턴

## 진행 순서

1. [theory.md](./theory.md) — 운영 관측 패턴 (25분)
2. [lab-01-ha-prometheus.md](./lab-01-ha-prometheus.md) — Prometheus HA + remote_write (30분)
3. [lab-02-amp.md](./lab-02-amp.md) — AWS Managed Prometheus 연결 (35분)
4. [lab-03-slo-alerts.md](./lab-03-slo-alerts.md) — Multi-burn-rate SLO alert (30분)
5. [lab-04-alertmanager-routing.md](./lab-04-alertmanager-routing.md) — 라우팅 / 억제 / 묵음 (25분)
6. [quiz.md](./quiz.md)
7. [pitfalls.md](./pitfalls.md)

## 비용

- AMP workspace: 메트릭 저장 + 쿼리 별 과금. 학습 1~2시간 약 0.1 USD
- 추가 리소스 거의 없음

## 본 커리큘럼 종료

이 모듈을 마치면 EKS 학습 커리큘럼 23개 모듈 전체 완료입니다 🎉.

```bash
# 모든 학습 끝났다면 클러스터 정리
eksctl delete cluster --name eks-study --region ap-northeast-2
```
