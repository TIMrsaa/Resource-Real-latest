# Lab 03 — Grafana Unified Alerting

> **🌱 Grafana Unified Alerting 이 뭔가?**
> Grafana 8+ 의 통합 알람 시스템. 여러 datasource (Prometheus, CloudWatch, Loki, MySQL...) 알람을 **한 UI 에서 관리**.
>
> **3가지 핵심 개념**:
> - **Alert Rule**: 평가할 쿼리 + 임계값 + 평가 주기
> - **Contact Point**: 알림 받을 곳 (Slack, Email, PagerDuty, Webhook)
> - **Notification Policy**: 어떤 alert 가 어떤 contact point 로 갈지 라우팅 (라벨 매칭)
>
> **흐름**:
> ```
>   Alert Rule → 조건 만족 → Pending → for: 통과 → Firing
>     → Notification Policy 가 라벨 매칭으로 contact point 결정
>     → contact point 로 메시지 발송 (Slack/Email/...)
> ```

## 1. Grafana Alerting 활성화 확인

http://localhost:3000 → 좌측 Alerting 메뉴.

기본은 active. Helm values 에서 토글 가능 (`grafana.alerting.unifiedAlerting.enabled`).

> **🧠 Legacy Alerting vs Unified Alerting**
> Grafana 7 까지 panel 기반 알람 (각 패널마다 알람) — legacy.
> Grafana 8+ unified — 패널과 분리, 별도 rule 관리.
>
> Legacy 의 한계:
> - 알람이 패널 종속 (대시보드 삭제 = 알람 사라짐)
> - 라벨/라우팅 빈약
>
> Unified 권장. 새 환경은 무조건 unified.

## 2. Contact Point 설정

Alerting → Contact points → New contact point.

옵션들:
- Email
- Slack (webhook URL)
- PagerDuty
- Webhook (custom)
- ...

학습용 — Webhook 으로 webhook.site 같은 테스트 endpoint:
- Name: `test-webhook`
- Type: Webhook
- URL: https://webhook.site/<unique-id>

> **🧠 Webhook 이 만능 contact point**
> 위에 없는 도구 (Discord, Teams, MS Teams, 사내 IM) 도 webhook 으로 통합 가능.
> Grafana 가 JSON payload 를 POST → 받는 쪽이 자기 형식으로 변환.
>
> **payload 구조** (대략):
> ```json
> {
>   "alerts": [{
>     "status": "firing",
>     "labels": {"severity": "critical", "service": "order"},
>     "annotations": {"summary": "..."},
>     "startsAt": "...",
>     "generatorURL": "..."
>   }]
> }
> ```
> 받는 서비스가 이 형식 파싱 후 자기 메시지로 변환 (예: AWS Lambda → Slack 변환).

## 3. Notification Policy

Alerting → Notification policies. Default policy 와 routing.

```
Default: contact point = test-webhook
  ├── matchers: severity=critical → contact point = pagerduty
  └── matchers: severity=warning  → contact point = slack-warning
```

> **🧠 Notification Policy 의 트리 구조**
> Alertmanager 와 동일 — 트리 매칭. 첫 매칭 (또는 continue 옵션) 이 routing.
>
> ```
>   Default (catch-all)
>     ├─ severity=critical → PagerDuty (page 24/7)
>     ├─ severity=warning  → Slack #alerts
>     │     ├─ team=platform → Slack #platform-alerts
>     │     └─ team=app     → Slack #app-alerts
>     └─ env=staging        → Slack #staging-alerts (silent)
> ```
>
> **주요 옵션**:
> - `group_by`: 같은 라벨 set 알람 묶음 (스팸 방지) — `group_by: [alertname, service]`
> - `group_wait`: 첫 알람 후 같이 묶을 후속 대기 (30s)
> - `group_interval`: 같은 그룹 알람 재발송 간격 (5m)
> - `repeat_interval`: 미해결 알람 재공지 주기 (4h)

## 4. Alert Rule 만들기 (UI)

Alerting → Alert rules → New rule.

### 4.1 Grafana managed (datasource agnostic)

Section A — Set query:
- Datasource: Prometheus
- Query: `sum by (service) (rate(http_requests_total{code=~"5.."}[5m])) / sum by (service) (rate(http_requests_total[5m]))`

Section B — Define alert:
- Reduce: `last()` 또는 `mean()`
- Threshold: `IS ABOVE 0.05`

Section C — Set evaluation:
- Folder: `EKS-Study`
- Group: `web-alerts`
- Evaluation: every `1m` for `5m`

Section D — Annotations + labels:
- summary: "{{ $labels.service }} error rate {{ humanizePercentage $value }}"
- severity: warning

Save.

> **🧠 Grafana managed vs Datasource managed 의 차이**
> - **Grafana managed**: Grafana 가 직접 평가 (Section A → B 단계 분리)
>   - 다중 datasource 결합 가능 (Prometheus + CloudWatch JOIN)
>   - 평가 주체가 Grafana → Grafana 다운 시 알람 끊김
> - **Datasource managed**: PrometheusRule 처럼 datasource 자체에 위임
>   - 평가는 Prometheus, Grafana 는 디스플레이만
>   - HA 측면에서 안정 (Prometheus 가 평가 책임)
>
> 운영: Prometheus 만 쓰면 datasource managed (PrometheusRule CRD), 다중 datasource 면 Grafana managed.

> **🧠 `{{ $labels.X }}`, `{{ $value }}` 템플릿**
> Go template 문법.
> - `$labels` = 알람의 라벨 map (`{{ $labels.service }}` = "order")
> - `$value` = 평가 결과 숫자
> - `humanizePercentage` = 0.067 → "6.7%" 변환
> - `humanize` = 1234.5 → "1.23 K"
> - `humanizeDuration` = 90 → "1m 30s"
>
> 알람 메시지가 사람이 즉시 이해 가능하도록 — page 받자마자 컨텍스트 파악.

## 5. Alert State

Alerting → Alert rules → 위 규칙:
- Normal — 조건 미충족
- Pending — 충족 시작 (for 안 끝남)
- Firing — for 끝나고 통지 발송

> **🧠 알람 state 와 noise 관리**
> - `Pending` 단계가 spam filter — 일시 spike 는 여기서 끝남
> - 너무 짧은 `for:` = noise (false positive)
> - 너무 긴 `for:` = late detection (사고 후 인지)
>
> **Pending → Firing 통계**: Grafana 의 alert state history 로 분석.
> Pending 만 자주 발생 / Firing 직전 회복 = 임계값이 너무 낮음 (false positive 후보).

## 6. Code 로 Alert Rule (provisioning)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-alerts
  namespace: monitoring
  labels:
    grafana_alert: "1"
data:
  alerts.yaml: |
    apiVersion: 1
    groups:
      - orgId: 1
        name: web
        folder: EKS-Study
        interval: 1m
        rules:
          - uid: high-error-rate
            title: High Error Rate
            condition: B
            data:
              - refId: A
                datasourceUid: prometheus
                model:
                  expr: 'sum by (service) (rate(http_requests_total{code=~"5.."}[5m])) / sum by (service) (rate(http_requests_total[5m]))'
              - refId: B
                datasourceUid: __expr__
                model:
                  type: threshold
                  expression: A
                  conditions:
                    - evaluator: {type: gt, params: [0.05]}
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "{{ $labels.service }} error rate {{ humanizePercentage $value }}"
```

> **🧠 `refId` 와 `condition` 의 의미**
> - 각 query/expression 은 `refId` (A, B, C...) 로 식별
> - `condition` = 어떤 refId 가 alert 트리거 결정
> - `__expr__` = Grafana 의 server-side expression engine
>
> 위 예: A (PromQL) → B (threshold check) → B 가 true 면 alert.
> 더 복잡한 케이스: A AND B (두 조건 동시) — `math` 또는 `classic_condition` 노드 사용.

## 7. Grafana Alerting vs Prometheus Alertmanager

| | Grafana Alerting | Prometheus Alertmanager |
|---|---|---|
| 데이터 소스 | 모든 datasource | Prometheus 만 |
| 평가 | Grafana 가 | Prometheus 가 |
| 라우팅 | Grafana 의 Notification policies | Alertmanager config |
| Multi-cluster | 한 Grafana 에서 통합 | 클러스터별 Alertmanager |
| 코드화 | provisioning ConfigMap | PrometheusRule CRD |

권장:
- 단일 클러스터 / Prometheus 중심 → **Alertmanager**
- 다중 datasource (CloudWatch + Prom + Loki) → **Grafana Alerting**
- 둘 다 → 가능 but 알람 중복 주의

> **🧠 둘 다 동시 운영 시 패턴**
> 흔한 함정: 같은 알람 두 곳에 정의 → Slack 메시지 2번 (중복 page).
>
> **분리 전략**:
> - **Alertmanager**: K8s/시스템 (Prometheus 메트릭 기반) — `kube_*`, `node_*`
> - **Grafana Alerting**: 비즈니스/멀티소스 — CloudWatch billing, Loki log pattern, multi-cluster aggregate
>
> 라우팅 prefix 도 분리: AM 은 `[k8s-alert]`, Grafana 는 `[biz-alert]` 형식.

## 학습 확인

1. Grafana Alerting 의 평가 주체는?
2. Prometheus Alertmanager 와 Grafana Alerting 을 동시 사용 시 주의점?
3. Webhook contact point 의 페이로드 형식은?

> **힌트**:
> 1. Grafana managed 면 Grafana 자체. Datasource managed 면 datasource (Prometheus). HA 측면에서 후자가 안정 (Grafana 다운에도 알람 살아있음).
> 2. 같은 메트릭에 알람 두 곳 정의 → 중복 통보. 룰을 명확히 분담 (예: K8s 시스템 = AM, 비즈니스/멀티 datasource = Grafana). 라벨 prefix 로 구분.
> 3. JSON: { alerts: [{ status, labels, annotations, startsAt, ... }] }. 받는 쪽이 자기 형식 (Slack/Discord) 으로 변환.

다음: [quiz.md](./quiz.md)
