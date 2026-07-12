# 이론 — Grafana 심화

> **🌱 Grafana = "자동차의 다중 계기판"**
> Prometheus 는 *센서들의 데이터* 자체, Grafana 는 *운전자가 보는 대시보드*.
> 한 화면에 속도 (메트릭), 주행 일지 (로그), 경로 (트레이스) 가 같이 떠야 운전자 (운영자) 가 빠르게 판단 가능 — 그래서 Grafana 는 *다중 datasource 통합* 이 강점.

## 1. Datasource

Grafana 가 데이터를 가져오는 외부 시스템:
- Prometheus (가장 흔함)
- CloudWatch
- Loki (로그)
- Tempo (트레이스)
- MySQL / Postgres
- Elasticsearch

여러 datasource 동시 사용 가능 → 한 대시보드 안에서 metrics + logs + traces.

> **🧠 "한 대시보드에 여러 datasource = *상관관계 분석* 의 무기"**
> 메트릭은 *문제 발생 시각* 을, 로그는 *그 순간 무엇이* 를 한 화면에서 볼 수 있다.
> Loki + Prometheus 조합이 그래서 강력 — 동일 라벨 (namespace, pod) 로 즉시 jump 가능.

## 2. Panel 종류

- **Time series** — 시간 축 그래프 (가장 흔함)
- **Stat** — 단일 큰 숫자
- **Gauge** — 게이지 (0 ~ 100%)
- **Bar gauge** — 다중 값 비교
- **Table** — 테이블
- **Heatmap** — 히트맵 (latency 분포 시각화 강력)
- **Logs** — Loki 결과
- **Trace** — Tempo 결과

> **🧠 "Heatmap 이 latency 시각화의 끝판왕"**
> 평균/p99 line graph 는 *분포를 숨긴다* — 큰 outlier 가 평균에 흡수되거나 p99 하나로 표현.
> Heatmap 은 *모든 bucket 의 농도* 를 보여줘서 "갑자기 50~80ms 대역이 진해짐" 같은 *패턴 변화* 까지 잡힌다.

## 3. Variables — 동적 drop-down

대시보드 상단의 drop-down 으로 query 의 일부를 사용자가 선택.

### 3.1 Query 변수

```
Name: namespace
Type: Query
Datasource: Prometheus
Query: label_values(kube_pod_info, namespace)
```

→ Prometheus 에서 namespace 라벨 unique 값들을 자동 채움.

### 3.2 사용
PromQL 안에 `$namespace`:
```
sum by (pod) (rate(http_requests_total{namespace="$namespace"}[1m]))
```

### 3.3 다른 변수 타입
- Constant — 상수
- Custom — 직접 입력
- Interval — `1m`, `5m`, `1h` (집계 단위)
- Datasource — 데이터소스 선택
- Text box — 자유 입력

### 3.4 Cascading
한 변수가 다른 변수에 의존:
```
$namespace ─→ $pod (Query: label_values(kube_pod_info{namespace="$namespace"}, pod))
```

> **🧠 "변수 = *한 대시보드를 N 개로 만들지 마라*"**
> namespace 마다 대시보드 5개 → 6개 NS 면 30개 — 운영 부담.
> 변수 1개로 대시보드 1개를 *모든 NS 에 재사용* 가능 — 변경 시 한 곳만 고침.

## 4. Annotations

대시보드 위에 **이벤트 마커** 표시:
- 배포 시각
- 사고 시각
- alert 발생 시각

```yaml
# Datasource: Prometheus
# Query: ALERTS{alertstate="firing"}
```

→ alert 발생 시점이 그래프 위에 빨간 줄.

> **🧠 "Annotation 은 *원인-결과* 의 시각적 다리"**
> "20:30 에 5xx 폭증" 그래프 위에 *20:25 배포 annotation* 이 같이 떠 있으면 원인 즉시 파악.
> CD 파이프라인이 *배포 시각을 annotation 으로 push* 하게 만드는 게 좋은 통합 패턴.

## 5. Links

- **Dashboard links**: 한 대시보드 → 다른 대시보드 (변수 전달)
- **Panel links**: 패널 → 외부 URL
- **Data links**: 데이터 포인트 클릭 → URL (예: pod 이름 클릭 → kubectl describe 페이지)

> **🧠 "Data Link 가 *대시보드를 콘솔로* 만든다"**
> 그래프의 spike 클릭 → 해당 pod 의 로그 / 트레이스 / runbook 즉시 이동.
> click-to-investigate 흐름이 잘 짜이면 *장애 평균 해결 시간 (MTTR)* 이 절반으로.

## 6. Provisioning — 대시보드를 코드로 관리

GUI 로 만든 대시보드를 git 에 저장 → 재배포 시 자동 적용.

### 6.1 ConfigMap 기반 (kube-prometheus-stack 의 sidecar)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  labels:
    grafana_dashboard: "1"     # ← sidecar 가 이 라벨 monitor
data:
  my-dashboard.json: |
    {
      "title": "My Dashboard",
      "panels": [...]
    }
```

→ Grafana sidecar 가 자동 import.

### 6.2 Datasource provisioning

```yaml
apiVersion: 1
datasources:
  - name: Prometheus-DC1
    type: prometheus
    url: http://prom-dc1:9090
  - name: Prometheus-DC2
    type: prometheus
    url: http://prom-dc2:9090
```

> **🧠 "GUI 대시보드는 *반드시* JSON 으로 export 후 git 보관"**
> Grafana DB 가 손상되면 *수개월 작업 한순간에 증발*.
> Provisioning (ConfigMap / GitOps) 로 *코드 = 진실 source* 패턴이 안전 + 협업도 가능.

## 7. Grafana 자체 Alerting (Unified Alerting)

Grafana 9+ 에서 통합 alerting:
- Prometheus / CloudWatch / Loki 등 **모든 datasource** 의 데이터로 alert
- Alertmanager 와 별도 (또는 Alertmanager 통합 가능)
- Slack, PagerDuty 등 contact point 통합

### 7.1 Alert Rule 만들기 (UI)
1. 대시보드 패널 → Alert 탭
2. Query 정의 (Prometheus / CloudWatch / ...)
3. Condition (예: `WHEN avg() OF query(A, 5m, now) IS ABOVE 0.05`)
4. Evaluation interval + for
5. Notification: contact point 선택

### 7.2 Code-based (UI 만든 후 export 또는 직접 작성)
```yaml
groups:
  - name: web-alerts
    rules:
      - uid: high-latency
        title: High Latency
        condition: A
        data:
          - refId: A
            datasourceUid: prometheus-uid
            model:
              expr: 'histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))'
        for: 5m
```

> **🧠 "Grafana Alerting vs Prometheus Alertmanager — 한쪽만"**
> 둘 다 alert 보내면 같은 사건에 *2번씩 notification* → 사람이 무뎌진다.
> 모든 datasource 통합 필요면 Grafana, Prometheus 단일 환경이면 Alertmanager — 둘 중 하나로 표준화.

## 8. 대시보드 디자인 best practice

1. **Top → Bottom** 정보의 폭 순 (overview → detail)
2. **단위 표시** (rps, %, ms, MB)
3. **색상 일관성** — green=good, red=bad
4. **임계값 표시** (Stat / Gauge 패널의 threshold)
5. **변수로 재사용성** — 같은 대시보드를 NS / 환경 별로
6. **너무 많은 패널 X** — 한 화면에 8~12개 권장

> **🧠 "대시보드는 *한 가지 질문에 답하는 도구*"**
> "RED 가 정상인지" / "노드 자원이 충분한지" / "비용이 추세대로인지" — 각각 별도 대시보드.
> 한 대시보드에 *모든 정보를 욱여넣으면* 결국 *어디서 시작해야 할지* 모르고 아무도 안 본다.

다음: [lab-01-variables.md](./lab-01-variables.md)
