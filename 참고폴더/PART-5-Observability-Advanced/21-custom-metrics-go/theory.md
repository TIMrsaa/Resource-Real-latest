# 이론 — prometheus/client_golang

> **🌱 Custom Metrics = "내 앱이 직접 우편함을 만든다"**
> Prometheus 가 모든 걸 자동 측정하지 않는다 — 비즈니스 지표 (주문 수, 결제 실패율) 는 *내가 직접 카운터를 만들어 노출* 해야 한다.
> 라벨 1개 선택이 *시계열 폭발* 을 부르거나 *알람을 정확하게* 만들기도 한다 — 라벨 설계가 metrics 의 90%.

## 1. 메트릭 등록 모델

```go
import "github.com/prometheus/client_golang/prometheus"

// 1. 메트릭 정의
var requestsTotal = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Total HTTP requests",
    },
    []string{"method", "path", "code"},     // 라벨
)

// 2. 등록
func init() {
    prometheus.MustRegister(requestsTotal)
}

// 3. 사용
requestsTotal.WithLabelValues("POST", "/orders", "200").Inc()
```

> **🧠 "MustRegister 가 *시작 시* panic 으로 실수를 잡아준다"**
> 같은 이름의 메트릭을 두 번 등록하면 즉시 panic — 런타임이 아니라 앱 부팅 단계에서 에러.
> 이게 *프로덕션에서 mute 한 메트릭 누수* 를 막는 first defense.

## 2. 메트릭 타입별 API

### 2.1 Counter / CounterVec
```go
var counter = prometheus.NewCounter(prometheus.CounterOpts{Name: "x_total"})
counter.Inc()
counter.Add(5)

var counterVec = prometheus.NewCounterVec(
    prometheus.CounterOpts{Name: "y_total"},
    []string{"label1", "label2"},
)
counterVec.WithLabelValues("a", "b").Inc()
```

### 2.2 Gauge / GaugeVec
```go
var gauge = prometheus.NewGauge(prometheus.GaugeOpts{Name: "active_connections"})
gauge.Inc()
gauge.Dec()
gauge.Set(42)
```

### 2.3 Histogram / HistogramVec
```go
var hist = prometheus.NewHistogramVec(
    prometheus.HistogramOpts{
        Name: "request_duration_seconds",
        Buckets: prometheus.DefBuckets,    // 또는 커스텀: []float64{.005, .01, .025, ...}
    },
    []string{"method", "path"},
)

// 사용
start := time.Now()
// ... 처리 ...
hist.WithLabelValues("POST", "/orders").Observe(time.Since(start).Seconds())
```

`DefBuckets`: `.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10` (초 단위 — HTTP 적합).

### 2.4 Summary
**가급적 사용 자제** (분산 환경 quantile 합산 불가).

> **🧠 "Counter 는 `_total` 접미사 — 단순 규칙이지만 강력"**
> Prometheus 는 `_total` 로 끝나는 메트릭을 *Counter 로 가정* 하고 rate 함수 자동 추천.
> 명명 규칙을 따르지 않으면 도구 (Grafana, Alertmanager) 의 helper 가 잘못 동작 — 작은 규칙이 큰 편의로 돌아온다.

## 3. 라벨 설계 best practice

### 좋은 라벨
- `method`: GET/POST/...   (값 4~7개)
- `path`: 라우트 패턴 (값 N개 — N = 라우트 수)
- `code`: HTTP status (200, 4xx, 5xx 그룹화 권장)

### 나쁜 라벨
- `user_id`, `request_id`, `email` — cardinality 폭발
- `timestamp` — 무한
- `random` — 무한

### path 라벨의 함정

```go
// ❌ /orders/abc-123-def 의 abc-123-def 가 path 로
labelValues := r.URL.Path

// ✅ 라우트 패턴 사용
labelValues := matchedRoute   // /orders/:id
```

Gin / Echo / chi 모두 matched route 를 노출.

> **🧠 "URL.Path 를 그대로 라벨에 넣으면 *시계열 무한 폭발*"**
> `/orders/abc-123` `/orders/def-456` 가 각각 별도 시계열로 저장 — 사용자당 시계열 생성.
> *라우트 패턴* (`/orders/:id`) 만 라벨로 — Gin 의 `c.FullPath()`, chi 의 `chi.RouteContext(r.Context()).RoutePattern()`.

## 4. promhttp.Handler 로 endpoint 노출

```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

http.Handle("/metrics", promhttp.Handler())
```

`promhttp.Handler()` 는 **모든 등록된 메트릭** 을 자동으로 노출.

### 별도 포트 권장
앱 트래픽 (8080) 과 메트릭 (9090) 분리 — Prometheus 가 앱 포트로 뚫지 않게.

> **🧠 "메트릭 포트는 *내부 전용* — ALB 에 노출 X"**
> 메트릭 endpoint 가 외부에 노출되면 *민감한 내부 정보 누출* + DDoS 위험.
> NetworkPolicy 로 *Prometheus Pod 만* 9090 접근 허용 — 보안과 비용 양쪽에 이득.

## 5. middleware 패턴 (Gin 예시)

```go
func PrometheusMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        c.Next()    // 핸들러 실행

        duration := time.Since(start).Seconds()
        path := c.FullPath()         // 라우트 패턴 (e.g., "/orders/:id")
        status := strconv.Itoa(c.Writer.Status())
        method := c.Request.Method

        requestsTotal.WithLabelValues(method, path, status).Inc()
        requestDuration.WithLabelValues(method, path).Observe(duration)
    }
}
```

> **🧠 "middleware 한 곳에서 모든 RED 가 끝난다"**
> RED (Rate, Errors, Duration) 를 *서비스마다 일관되게* 측정하려면 코드 분산이 아니라 middleware 가 정답.
> 새 핸들러 추가해도 자동 측정 — 일관성 + 신규 코드 부담 0.

## 6. Histogram bucket 설계

기본 `DefBuckets` 는 일반 HTTP 적합. 그러나 워크로드 특성에 맞춰 조정:

- API 게이트웨이: `[.001, .005, .01, .025, .05, .1, .25, .5, 1]` (낮은 값에 더 dense)
- 배치 작업: `[1, 5, 10, 30, 60, 300, 600]` (분 단위)
- gRPC: `[.001, .002, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5]`

너무 많은 bucket → cardinality (`bucket × 라벨 조합`).

> **🧠 "bucket 은 *SLO 임계값에 맞춰* 설계하라"**
> p99 < 500ms SLO 라면 bucket 에 `[..., 0.25, 0.5, 1, ...]` 같이 *500ms 근처 해상도* 가 필요.
> 기본값 (DefBuckets) 으로 SLO 측정하면 임계값 근처 데이터가 sparse 해 정확한 p99 산출 불가.

## 7. 표준 메트릭 (Go runtime / process)

`promhttp.Handler()` 가 자동 노출하는 표준 메트릭:
- `go_goroutines`, `go_memstats_*` — Go runtime
- `process_cpu_seconds_total`, `process_resident_memory_bytes` — OS process

대시보드 (Grafana ID 6671 — Go Processes) 그대로 사용 가능.

> **🧠 "Go runtime 메트릭은 *공짜로 얻는 정보* — 켜둬라"**
> goroutine 누수 / GC 부담 / 메모리 사용을 한 줄 핸들러로 측정 가능.
> 6671 대시보드를 import 하면 *별도 작업 없이* GC pause 같은 깊은 진단까지 가능.

## 8. 추천 패턴 — `shared/metrics` 라이브러리

본 커리큘럼 다음 lab 에서 `shared/metrics/` 를 확장:
- 모든 서비스가 표준 메트릭 자동 노출
- `RED()` 헬퍼로 middleware 한 줄 적용
- `Gauge()`, `Counter()` 빌더로 커스텀 추가

> **🧠 "공통 라이브러리가 *조직 단위 관측성 표준* 의 핵심"**
> 서비스마다 다른 메트릭 이름 / 라벨 → 대시보드 / 알람 / SLO 자동화 불가능.
> shared/metrics 같은 사내 표준 lib 으로 *모두가 같은 이름 / 같은 라벨* 을 쓰게 만드는 게 운영 옵저버빌리티의 진짜 toolkit.

다음: [lab-01-shared-metrics.md](./lab-01-shared-metrics.md)
