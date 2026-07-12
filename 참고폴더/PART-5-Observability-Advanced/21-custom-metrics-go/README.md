# 21. Custom Metrics in Go

## 학습 목표

`prometheus/client_golang` 라이브러리로 시나리오 앱에 메트릭 직접 추가:

- Counter (요청 수)
- Histogram (지연 시간)
- Gauge (활성 연결 수, 큐 크기)
- 라벨 설계 best practice

`scenarios/shared/metrics/` 모듈을 확장해 모든 서비스가 표준 RED 메트릭을 자동 노출하도록.

## 선행 지식

- 모듈 19, 20 완료
- Go 기초

## 진행 순서

1. [theory.md](./theory.md) — client_golang 설계 (15분)
2. [lab-01-shared-metrics.md](./lab-01-shared-metrics.md) — `shared/metrics` 확장 (40분)
3. [lab-02-instrument-services.md](./lab-02-instrument-services.md) — 5개 서비스에 적용 (40분)
4. [quiz.md](./quiz.md)
5. [pitfalls.md](./pitfalls.md)

## 다음 모듈

→ [22-grafana-advanced](../22-grafana-advanced/)
