# Part 5 — Observability 심화 (Prometheus + Grafana)

> **💡 일상 비유로 이해하기**
>
> 대형 프랜차이즈 본사가 전국 매장의 매출/방문자/대기시간을 실시간으로 추적하는 상황을 떠올려보세요. 매장마다 사장이 직접 가서 묻는 게 아니라, 본사가 자동으로 매장의 POS에서 숫자를 긁어오고(Prometheus), 보기 좋은 차트로 그려서(Grafana), 이상하면 매니저에게 알림을 보내는(Alertmanager) 통합 관제센터를 만드는 일입니다. Part 5에서는 이 관제센터를 운영 수준으로 직접 구축합니다.

## 학습 목표

Module 08 (P2) 에서 다룬 기초를 넘어, **운영 수준의 관측 스택** 을 직접 구축한다.

- Prometheus 아키텍처와 동작 원리 (TSDB, scrape, federation)
- PromQL 쿼리 4가지 메트릭 타입 + recording rules
- 시나리오 Go 앱에 직접 메트릭 추가 (RED 패턴)
- Grafana 변수 / Provisioning / 자체 Alerting
- 운영 (HA, 장기 저장소, SLO/SLI, Alertmanager 라우팅)

## 모듈 구성

| 번호 | 모듈 | 핵심 |
|------|------|------|
| 19 | [prometheus-deep-dive](./19-prometheus-deep-dive/) | 아키텍처, TSDB, ServiceMonitor 심화, federation |
| 20 | [promql-mastery](./20-promql-mastery/) | 4 메트릭 타입, RED/USE, recording rules |
| 21 | [custom-metrics-go](./21-custom-metrics-go/) | scenarios Go 앱에 Counter/Histogram 추가 |
| 22 | [grafana-advanced](./22-grafana-advanced/) | Variables, Provisioning, Grafana Alerting |
| 23 | [production-observability](./23-production-observability/) | HA, Thanos/AMP, SLO, Alertmanager routing |

## 선행 지식

- Part 1~4 완료 (특히 Module 08)
- Go 기초 (Module 21 의 코드 변경 위해)

## 비용 (Part 5 전체)

- 5개 모듈 × 평균 1.5시간 = 7.5시간
- 기존 monitoring 스택 위에 추가 컴포넌트 (Thanos, Alertmanager Webhook 등)
- 약 2 ~ 3 USD

## Module 08 와의 관계

| 항목 | Module 08 (P2) | Part 5 (P5) |
|------|----------------|-------------|
| 설치 | kube-prometheus-stack 한 번 | 깊은 설정 (HA, retention, 외부 storage) |
| ServiceMonitor | 사용 | 만드는 법 + 동작 원리 |
| Grafana | 대시보드 import | 자체 작성 + provisioning |
| Alert | PrometheusRule 1개 | 라우팅 + SLO + multi-burn-rate |
| 메트릭 | 기본 노출 메트릭 | 앱에 직접 추가 |

## 다음 단계

이 Part 가 끝나면 본 커리큘럼의 모든 기능 영역 (인프라 + K8s + 자동 스케일 + 운영 + 관측 심화) 을 다 다룬 셈입니다.
