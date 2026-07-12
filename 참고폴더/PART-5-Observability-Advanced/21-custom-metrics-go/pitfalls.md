# 흔한 함정 5선 — 21. Custom Metrics in Go

## 1. URL.Path 를 라벨로 → cardinality 폭발

**증상**: Prometheus 메모리 폭증. `http_requests_total` 의 시계열 수가 100,000+.

**원인**: `r.URL.Path = "/orders/abc-123-def-..."` 같은 고유 ID 가 path 라벨로.

**해결**: 라우터의 matched route 사용:
- Gin: `c.FullPath()`
- Echo: `c.Path()`
- chi: `chi.RouteContext(r.Context()).RoutePattern()`
- net/http: 직접 라우트 매핑 작성

---

## 2. 같은 메트릭 두 번 등록 panic

**증상**:
```
panic: duplicate metrics collector registration attempted
```

**원인**: 같은 이름 + 같은 라벨로 두 번 등록 (예: hot reload 또는 init 두 번).

**해결**:
- `promauto` 사용 (자동 처리)
- 또는 `prometheus.Register` (panic 안 하고 error 반환)
- 패키지 init 에서 한 번만

---

## 3. Histogram bucket 너무 많음 → cardinality

**증상**: histogram 메트릭 1개가 시계열 100,000+.

**원인**:
```go
Buckets: prometheus.LinearBuckets(0, 0.001, 1000)    // 1000 bucket!
```

**해결**:
- bucket 10~15개 권장
- 워크로드 특성에 맞는 분포로 (DefBuckets 또는 ExponentialBuckets)
- 라벨 조합 × bucket 수 = 시계열. 4 × 5 × 10 = 200 OK, 100 × 100 × 100 = 1M ❌

---

## 4. Histogram Observe 호출 누락

**증상**: `_count`, `_sum` 은 있는데 `_bucket` 시계열 없음.

**원인**: Histogram 의 `Observe()` 가 한 번도 호출 안 됨 → bucket 시계열 lazy 생성 안 함.

**해결**: 미리 등록:
```go
hist.WithLabelValues("dummy").Observe(0)
```

또는 첫 요청 후에 정상 노출되니 trigger 발생 후 확인.

---

## 5. Gauge 의 Inc/Dec 페어링 실수

**증상**: `in_flight` 가 음수로 가거나 영원히 늘기만.

**원인**: 어떤 경로에서 `Inc()` 만 하고 `Dec()` 누락 (panic 발생 시 등).

**해결**: `defer` 사용:
```go
inFlight.WithLabelValues("svc").Inc()
defer inFlight.WithLabelValues("svc").Dec()

// 어떤 일이 있어도 Dec
```

또는 `WithLabelValues(...).Add(1); defer .Add(-1)` 패턴.
