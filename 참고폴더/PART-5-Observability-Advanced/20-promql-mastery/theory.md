# 이론 — PromQL Mastery

> **🌱 PromQL = "데이터 시계열에 던지는 회화체 질문"**
> SQL 이 *행/열 테이블* 을 다룬다면, PromQL 은 *시간 위에 흐르는 값들* 을 다룬다.
> Counter 는 마라톤 누적 거리 (rate 가 속도), Gauge 는 지금 체온, Histogram 은 마라톤 참가자들의 완주시간 분포 — 메트릭 타입의 비유로 PromQL 함수 선택이 명확해진다.

## 1. 4가지 메트릭 타입

### 1.1 Counter — 단조 증가

**의미**: 시작 후 누적량. 절대 안 줄어듦 (재시작 시 0 으로 리셋).

**예**:
```
http_requests_total
errors_total
bytes_sent_total
```

**naming 규칙**: `_total` suffix 권장.

**쿼리는 절대값이 아니라 rate**:
```promql
# 지난 1분간 RPS
rate(http_requests_total[1m])

# 지난 5분 RPS (smoother)
rate(http_requests_total[5m])

# 즉시 RPS (last 2 samples)
irate(http_requests_total[1m])
```

`rate` vs `irate`:
- rate: range 의 평균 (smooth)
- irate: 마지막 2 샘플의 차이 (즉각, 노이즈 ↑)

대시보드는 rate, alert 는 보통 rate (안정적).

### 1.2 Gauge — 임의로 오르내림

**의미**: 어느 순간의 값.

**예**:
```
goroutines_count
memory_bytes
queue_length
temperature_celsius
```

**쿼리는 그대로**:
```promql
# 현재 메모리
node_memory_MemAvailable_bytes

# 변화량 (rate 사용 X — 의미 없음)
delta(queue_length[5m])
```

### 1.3 Histogram — bucket 별 카운트

**의미**: 분포를 미리 정한 bucket 으로 누적. 서버 측에서 quantile 계산 가능.

**예** (latency):
```
http_request_duration_seconds_bucket{le="0.005"}  → ≤5ms 응답 수
http_request_duration_seconds_bucket{le="0.01"}   → ≤10ms 응답 수
http_request_duration_seconds_bucket{le="0.05"}   → ...
http_request_duration_seconds_bucket{le="+Inf"}   → 전체
http_request_duration_seconds_sum                 → 합산 시간
http_request_duration_seconds_count               → 호출 수
```

**쿼리** — p99 latency:
```promql
histogram_quantile(0.99,
  sum by (le, path) (rate(http_request_duration_seconds_bucket[5m]))
)
```

`sum by (le, path)` 가 핵심 — 여러 Pod 의 같은 path 의 bucket 을 합쳐서 quantile 계산.

**평균 latency**:
```promql
sum by (path) (rate(http_request_duration_seconds_sum[5m]))
  / sum by (path) (rate(http_request_duration_seconds_count[5m]))
```

### 1.4 Summary — quantile 직접 계산 (client 측)

**의미**: 클라이언트가 quantile (p50, p95, p99) 을 미리 계산.

**예**:
```
rpc_duration_seconds{quantile="0.5"}    → p50
rpc_duration_seconds{quantile="0.99"}   → p99
rpc_duration_seconds_sum
rpc_duration_seconds_count
```

**문제**: 여러 Pod 의 quantile 을 합산 못 함 (수학적으로). → 가능한 Histogram 권장.

> **🧠 "메트릭 타입은 *질문의 종류* 가 결정한다"**
> "얼마나 자주?" (RPS) → Counter / "지금 얼마?" (메모리) → Gauge / "분포는?" (latency p99) → Histogram.
> *Summary 는 단일 인스턴스만 측정* 할 때 유효 — 여러 Pod 의 p99 를 정확히 보려면 무조건 Histogram.

## 2. 자주 쓰는 함수

### 2.1 시간 함수
- `rate(metric[5m])` — Counter 의 초당 평균 증가
- `irate(metric[1m])` — 즉시 변화율 (마지막 2 샘플)
- `increase(metric[1h])` — range 동안 총 증가
- `delta(metric[5m])` — Gauge 의 차이
- `deriv(metric[5m])` — Gauge 의 초당 변화율 (회귀)

### 2.2 집계
- `sum`, `avg`, `max`, `min`, `count`
- `sum by (label) (...)` — 라벨별 집계
- `sum without (label) (...)` — 그 라벨만 제외하고 집계

```promql
# Pod 별 CPU
sum by (pod) (rate(container_cpu_usage_seconds_total[1m]))

# 노드별 합산 (pod 라벨 제거)
sum without (pod) (rate(container_cpu_usage_seconds_total[1m]))
```

### 2.3 vector matching
```promql
# CPU usage / CPU limit 비율
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="order"}[1m]))
  /
sum by (pod) (kube_pod_container_resource_limits{namespace="order",resource="cpu"})
```

label set 이 양쪽에서 매칭되어야. 안 맞으면 `on()` / `ignoring()` / `group_left` / `group_right` 사용.

### 2.4 topk / bottomk
```promql
topk(5, sum by (pod) (rate(http_requests_total[1m])))
```

> **🧠 "라벨 매칭 실패 = PromQL 디버깅 1위 함정"**
> 두 메트릭을 나누는데 결과가 `0 vectors` 면 *양쪽 라벨 set 이 다르다* 는 뜻.
> `on(pod)` / `ignoring(instance)` / `group_left` 로 명시적 조정 — 자동 매칭에 기대지 마라.

## 3. RED 메트릭 패턴 (서비스 레벨)

**R**ate, **E**rrors, **D**uration:
```promql
# Rate
sum by (service) (rate(http_requests_total[1m]))

# Errors
sum by (service) (rate(http_requests_total{status=~"5.."}[1m]))
  / sum by (service) (rate(http_requests_total[1m]))

# Duration (p99)
histogram_quantile(0.99, sum by (le, service) (rate(http_request_duration_seconds_bucket[5m])))
```

> **🧠 "RED 는 *사용자 관점*, 비즈니스 SLO 의 토대"**
> CPU/Memory 는 *내부 자원* — 사용자는 *서비스가 빠른가 / 에러가 적은가* 만 체감.
> SLO 설계 시 1순위는 RED 3가지 (Rate, Errors, Duration), 자원 메트릭 (USE) 은 *원인 분석용* 으로 보조.

## 4. USE 패턴 (자원 레벨)

**U**tilization, **S**aturation, **E**rrors:
- CPU utilization: `rate(node_cpu_seconds_total{mode!="idle"}[1m])`
- Memory utilization: `1 - (node_memory_MemAvailable / node_memory_MemTotal)`
- Disk saturation: `rate(node_disk_io_time_weighted_seconds_total[1m])`
- Network errors: `rate(node_network_receive_errs_total[1m])`

> **🧠 "RED → USE 순서로 봐라"**
> 장애 시 사용자 영향 (RED) 부터 확인 → 영향이 있으면 USE 로 원인 자원을 추적.
> USE 먼저 보면 *정상인 자원의 노이즈* 에 시간을 빼앗긴다.

## 5. Recording Rules — 비싼 쿼리 사전 계산

자주 쓰는 비싼 쿼리를 주기적으로 미리 계산 → 새 metric 으로 저장:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    release: kps
spec:
  groups:
    - name: recording.rules
      interval: 30s
      rules:
        - record: namespace:http_requests_per_second:sum
          expr: sum by (namespace) (rate(http_requests_total[1m]))

        - record: namespace:http_error_rate:ratio
          expr: |
            sum by (namespace) (rate(http_requests_total{status=~"5.."}[1m]))
              /
            sum by (namespace) (rate(http_requests_total[1m]))
```

**Naming convention**: `level:metric:operation` (Brian Brazil 규칙).

> **🧠 "Recording rule = *자주 푸는 수학문제의 답을 미리 적어두기*"**
> 대시보드가 무거우면 PromQL 비용이 원인 — 동일 쿼리를 매 새로고침마다 다시 계산.
> Recording rule 로 1회 계산 / 저장 → 대시보드는 *그 저장된 메트릭만 읽기* — 쿼리 비용 1/100.

## 6. Alert Rules

```yaml
groups:
  - name: app.alerts
    rules:
      - alert: HighErrorRate
        expr: namespace:http_error_rate:ratio > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.namespace }} error rate {{ $value | humanizePercentage }}"
```

`for: 5m` — 5분 동안 조건 유지되어야 alert. 일시적 spike 무시.

> **🧠 "`for` 가 alert 노이즈 vs 응답성의 trade-off"**
> 너무 짧으면 (1m) 노이즈 폭주, 너무 길면 (30m) 실제 장애 대응 늦음.
> SLO 등급에 따라 차등화 — *critical* 은 5m, *warning* 은 15m 정도가 균형점.

## 7. PromQL 안티패턴

| 패턴 | 문제 | 대안 |
|------|------|------|
| `rate(gauge[5m])` | Gauge 에 rate 의미 없음 | `delta` / `deriv` |
| `histogram_quantile(0.99, http_request_duration_seconds_bucket)` | rate 안 감싸 | `histogram_quantile(0.99, sum by(le)(rate(... [5m])))` |
| `sum(rate(...))` 라벨 없이 | 모든 라벨 합쳐 의미 상실 | `sum by (path)` 또는 `sum by (instance)` 등 |
| `avg(quantile)` (Summary) | 수학적 잘못 | Histogram 으로 마이그 |

> **🧠 "안티패턴의 공통점 = *메트릭 타입의 의미 무시*"**
> Counter / Gauge / Histogram 각자 *허용 함수* 가 정해져 있다 — 섞으면 결과는 나오지만 의미 없는 숫자.
> PromQL 쓰기 전에 *이 메트릭이 어떤 타입인지* 부터 확인하는 게 정확한 쿼리의 90%.

다음: [lab-01-query-patterns.md](./lab-01-query-patterns.md)
