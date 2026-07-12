# 이론 — Production Observability

> **🌱 운영 옵저버빌리티 = "병원의 24/7 ICU 모니터링"**
> 단일 모니터 (Prometheus 1대) 가 꺼지면 환자 (서비스) 의 위급 신호를 못 본다 — HA + 장기 보관이 필수.
> SLO 는 *환자의 vital sign 임계선*, Error Budget 은 *허용 가능한 위험 범위*, runbook 은 *간호사 매뉴얼* — 모두 함께 갖춰져야 진짜 운영 가능.

## 1. Prometheus HA — 두 가지 접근

### 1.1 다중 replicas (단순)

```yaml
prometheus.spec:
  replicas: 2
```

→ 두 Prometheus 가 같은 target 들을 각자 scrape. 중복 데이터.

**문제**:
- Grafana 가 두 source 를 동시 쓰면 그래프 중복
- 시각적으로 차이 (slight time skew)

**해결**: Querier (Thanos) 또는 dedup proxy 가 위에 위치 → Grafana 는 한 endpoint.

### 1.2 단일 + remote_write (중앙 저장소)

각 클러스터 (또는 region) Prometheus 1개 + remote_write 로 중앙 저장:

```yaml
remoteWrite:
  - url: https://central-storage/api/v1/write
```

중앙 저장소: Thanos / Mimir / Cortex / VictoriaMetrics / AMP.

→ HA 는 중앙 저장소가 책임.

> **🧠 "HA 의 *진짜 의미* 는 *Prom 1대 죽어도 알람이 계속 가는 것*"**
> 단순히 replicas 2 만 두는 건 *데이터 중복* 일 뿐, 알람/쿼리가 한 인스턴스에 의존하면 SPOF.
> Querier + dedup 로 *클라이언트는 단일 endpoint* 만 보게 만드는 게 진짜 HA.

## 2. 장기 저장 옵션 비교

### 2.1 Thanos
- Prometheus 옆 sidecar → S3 로 chunk 업로드
- Querier 가 여러 Prom + S3 통합 쿼리
- **장점**: 무한 retention (S3 비용만), Prom 기반이라 호환성 ↑
- **단점**: 컴포넌트 다수 (sidecar/store/compactor/querier)

### 2.2 Grafana Mimir / Cortex
- Push 기반 (remote_write)
- Multi-tenant 우수 (SaaS 수준)
- Microservices 아키텍처

### 2.3 AWS Managed Prometheus (AMP)
- AWS 가 운영하는 Cortex 호환 서비스
- IAM 인증 (sigv4)
- 15개월 retention
- 비용: ingestion + query 별
- **장점**: 운영 부담 0
- **단점**: AWS lock-in

### 2.4 VictoriaMetrics
- 단일 바이너리 (간단)
- 디스크/메모리 효율 ↑
- 일부 PromQL 호환성 차이

| | Thanos | Mimir | AMP | VM |
|---|---|---|---|---|
| 운영 부담 | 중 | 높 | 0 | 낮 |
| 비용 | S3 + Querier | 자체 운영 | per-sample | 자체 운영 |
| HA | ✓ | ✓ | ✓ | ✓ |
| 무한 retention | S3 | S3/GCS | 15개월 | 자체 디스크 |

**학습 환경**: AMP 추천 (AWS 자원 활용 + 운영 부담 0).

> **🧠 "어떤 도구든 *S3 가 무한 storage 의 정답*"**
> Thanos / Mimir 모두 결국 S3 위에 chunk 저장 — 디스크 가득 차서 문제 생길 일 없다.
> 자체 디스크 기반 (VictoriaMetrics 등) 은 빠르지만 *증설 운영 부담* 이 별도 — 선택의 trade-off.

## 3. SLI / SLO / Error Budget

### 3.1 정의

- **SLI** (Service Level Indicator) — 측정 메트릭 (예: 5xx 비율)
- **SLO** (Service Level Objective) — 목표 (예: 5xx < 0.1% over 30d)
- **Error Budget** — 1 - SLO. 이 만큼은 "허용된 에러"

### 3.2 좋은 SLI 의 특징

- **사용자 경험 반영** — 5xx 비율, p99 latency, 응답률
- **측정 가능** — Prometheus 메트릭으로
- **단순** — 하나의 숫자

흔한 SLI:
- **Availability**: `successful_requests / total_requests`
- **Latency**: `requests_under_500ms / total_requests`
- **Quality**: `requests_with_correct_data / total_requests`

### 3.3 SLO 정의

```
SLO: 30일 동안 99.9% 의 요청이 성공
Error Budget: 0.1% = 30일 × 24h × 60min × 0.001 = 43.2분 down time
```

> **🧠 "SLO 는 *제품팀과의 약속*, 사용자 체감 기준이지 내부 자원 기준 X"**
> CPU 사용률 SLO 는 무의미 — 사용자는 *내 요청이 빠르냐* 만 관심.
> Availability / Latency / Quality 3가지가 사용자 SLO 의 표준 출발점.

## 4. Multi-Burn-Rate Alert

기본 alert (`error_rate > 0.01 for 5m`) 의 문제:
- 빠른 사고 (1분 100% down) → 5m for 동안 통지 늦음
- 느린 사고 (10시간 동안 1% 에러) → 알림 안 옴 (임계 미달)

**Multi-burn-rate**: 두 윈도우 동시 평가:

```yaml
- alert: ErrorBudgetBurning_Fast
  expr: |
    sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.144 and
    sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h])) > 0.144
  for: 2m
  labels:
    severity: critical

- alert: ErrorBudgetBurning_Slow
  expr: |
    sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h])) > 0.018 and
    sum(rate(http_requests_total{status=~"5.."}[6h])) / sum(rate(http_requests_total[6h])) > 0.018
  for: 15m
  labels:
    severity: warning
```

각 burn rate 값은 SLO 와 budget consumption 시간으로 계산. 자세한 계산은 Google SRE Workbook 참고.

> **🧠 "단일 임계 alert 는 *느린 사고를 놓치고 빠른 사고에 늦는다*"**
> 5분 윈도우 하나만 보면 *짧은 spike* 와 *긴 누적* 둘 다 정확히 못 잡는다.
> Multi-burn-rate (빠른 윈도우 + 느린 윈도우 AND) 가 *진짜 budget consumption* 을 추적하는 정석.

## 5. Alertmanager 라우팅 / 억제 / 묵음

### 5.1 라우팅 (route)

```yaml
route:
  group_by: [alertname, namespace]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: default-slack
  routes:
    - matchers: [severity="critical"]
      receiver: pagerduty
      continue: true     # → 추가로 default 도 받음
    - matchers: [team="platform"]
      receiver: platform-slack
```

### 5.2 억제 (inhibition)

심각한 alert 가 firing 이면 덜 심각한 같은 시리즈 억제:
```yaml
inhibit_rules:
  - source_matchers: [severity="critical"]
    target_matchers: [severity="warning"]
    equal: [namespace, service]
```

→ critical 발생 시 같은 NS+service 의 warning 무시.

### 5.3 묵음 (silence)

운영 작업 (배포 / 점검) 중 일시적 alert 차단.
- Alertmanager UI 에서 시작 / 종료 시각 + matchers 입력
- API: `amtool silence add`

> **🧠 "라우팅 / 억제 / 묵음 = *on-call 의 정신건강*"**
> 라우팅 없이 모든 alert 가 한 채널로 → 노이즈, 사람이 무뎌짐.
> 억제 + 묵음 으로 *진짜 중요한 신호만* 사람에게 도달하게 만드는 게 alert design 의 핵심 목표.

## 6. Runbook annotation

alert 가 firing 시 즉시 무엇을 해야 할지:

```yaml
annotations:
  summary: "..."
  runbook_url: "https://wiki.example.com/runbooks/{{ $labels.alertname }}"
```

→ Slack 통지에 link 포함. on-call 이 즉시 절차 확인.

> **🧠 "runbook 없는 alert 는 *알람만 울리고 답이 없는 시스템*"**
> 새벽 2시에 깨어난 on-call 이 *무엇을 봐야 하고 무엇을 하면 안 되는지* 명시 안 된 alert 는 무용지물.
> 모든 alert 의 정의에 runbook_url 을 강제 — 없는 alert 는 *애초에 만들지 마라*.

## 7. Distributed Tracing 미리보기

본 커리큘럼 범위 외지만 언급:
- AWS X-Ray, Tempo, Jaeger
- OpenTelemetry SDK 로 앱 수정
- TraceID 를 로그/메트릭에 포함 → 3축 연결

> **🧠 "TraceID 가 *Metrics-Logs-Traces 의 본드*"**
> 같은 TraceID 로 *어떤 요청이 어디서 느렸는지 → 그 순간 로그 → 그 Pod 메트릭* 을 한 흐름으로 추적 가능.
> Tracing 도입의 가장 큰 가치는 *3축 데이터의 통합* — TraceID 만 잘 흘려보내면 도구는 선택의 문제.

다음: [lab-01-ha-prometheus.md](./lab-01-ha-prometheus.md)
