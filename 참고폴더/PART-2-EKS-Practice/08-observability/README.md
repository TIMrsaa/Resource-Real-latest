# 08. Observability — CloudWatch + kube-prometheus-stack

## 학습 목표

- 메트릭 / 로그 / 트레이스 3축 이해
- AWS 네이티브: **CloudWatch Container Insights** 셋업
- 오픈소스: **kube-prometheus-stack** (Prometheus + Grafana + Alertmanager)
- Grafana 대시보드 import + alert rule
- 로그 수집: **Fluent Bit** for CloudWatch Logs

## 선행 지식

- 모듈 05~07 완료
- IRSA 동작 이해 (CloudWatch agent / Fluent Bit 가 IRSA 사용)

## 진행 순서

1. [theory.md](./theory.md) — 관측 3축 + EKS 옵션 (15분)
2. [lab-01-cloudwatch.md](./lab-01-cloudwatch.md) — Container Insights 활성화 (25분)
3. [lab-02-prometheus.md](./lab-02-prometheus.md) — kube-prometheus-stack 설치 (35분)
4. [lab-03-grafana-alert.md](./lab-03-grafana-alert.md) — 대시보드 + alert (25분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 비용 주의

- CloudWatch Logs ingestion: $0.50/GB
- CloudWatch Metrics: 첫 10,000개 무료 → Container Insights 가 빠르게 채움
- 학습 끝나면 즉시 cleanup

학습 1.5시간 기준 약 1~2 USD 가능.

## 다음 모듈

→ [09-msa-deploy](../09-msa-deploy/)
