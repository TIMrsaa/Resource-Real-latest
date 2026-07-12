# 퀴즈 — 21. Custom Metrics in Go

### Q1. `promauto.NewCounterVec` 가 `prometheus.NewCounterVec + MustRegister` 보다 좋은 점은?

---

### Q2. Gin 의 `c.FullPath()` 와 `c.Request.URL.Path` 의 cardinality 영향 차이는?

---

### Q3. `inFlight` Gauge 가 RED 패턴의 어디에 해당? (R/E/D 외 4번째 차원?)

---

### Q4. Histogram 의 bucket 을 12개로 잡았다. 라벨 4종 × 각 5개 unique 면 시계열 수는?

---

### Q5. payment-service 같은 워커에서 RED 대신 어떤 메트릭이 적합?

---

### Q6. gRPC 메트릭에서 status code 의 표현은 (HTTP 와 다른 점)?

---

### Q7. `_total` suffix 가 있는 metric 에 `rate(...)` 안 감으면 어떤 일이?

---

### Q8. 같은 메트릭 이름 `http_requests_total` 을 여러 서비스가 노출. 라벨에 `service` 를 넣어야 하는 이유는?

---

### Q9. promhttp.Handler 가 자동 노출하는 표준 메트릭 카테고리 두 가지는?

---

### Q10. (실습 검증) order-service 의 `/orders/:id` GET 요청 RPS 만 보는 PromQL은?

---

## 정답

<details>

**Q1**: 자동 등록 + 중복 등록 panic 없이 안전. 짧은 코드.
**Q2**: FullPath 는 라우트 패턴 (/orders/:id) — cardinality 일정. URL.Path 는 실제 (/orders/abc-123) — cardinality 폭발.
**Q3**: Saturation (USE 의 S). RED + Saturation 으로 RED-S 또는 Four Golden Signals 의 일부.
**Q4**: 4×5 = 20 라벨 조합. 각 조합에 12 bucket + _sum + _count = 14 시계열. 총 20×14 = 280
**Q5**: 처리한 메시지 수 (Counter), 실패율, 처리 시간 Histogram, 큐 lag (Gauge)
**Q6**: gRPC 는 status code 가 OK / NotFound / Unavailable 등 텍스트 (메트릭 라벨에 그대로). HTTP 는 숫자.
**Q7**: 누적값 그대로 → 시각화/alert 에 의미 없음. rate 필수.
**Q8**: 같은 메트릭이 여러 서비스에서 합쳐 보이지 않게 / 서비스 별 분리해서 분석 가능
**Q9**: Go runtime (`go_*`), process (`process_*`)
**Q10**: `sum(rate(http_requests_total{service="order-service",method="GET",path="/orders/:id"}[1m]))`

</details>

다음: [pitfalls.md](./pitfalls.md)
