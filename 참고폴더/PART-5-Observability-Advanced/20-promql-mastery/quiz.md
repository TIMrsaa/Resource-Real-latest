# 퀴즈 — 20. PromQL Mastery

### Q1. 4가지 메트릭 타입과 각 1줄 정의를 적으세요.

---

### Q2. Counter 메트릭에 `_total` suffix 를 붙이는 이유는?

---

### Q3. `histogram_quantile(0.99, http_request_duration_seconds_bucket)` 가 잘못된 이유는?

---

### Q4. `rate(metric[5m])` 와 `irate(metric[1m])` 의 차이는?

---

### Q5. RED 패턴의 R/E/D 가 의미하는 것은?

---

### Q6. recording rule 을 쓰는 이유와 비용은?

---

### Q7. Summary 메트릭이 분산 환경에서 부적합한 이유는?

---

### Q8. `sum(rate(metric[1m]))` 와 `sum by (pod) (rate(metric[1m]))` 의 차이는?

---

### Q9. `for: 5m` 이 alert 에서 의미하는 것은?

---

### Q10. (실습) 클러스터에서 가장 5xx 에러를 많이 내는 서비스 5개를 보는 PromQL?

---

## 정답

<details>

**Q1**:
- Counter: 단조 증가 (재시작 시 0)
- Gauge: 임의로 오르내림
- Histogram: 미리 정의된 bucket 별 카운트 (서버 측 quantile)
- Summary: 클라이언트가 quantile 직접 계산
**Q2**: convention — Counter 임을 명확히. 도구가 자동 인식.
**Q3**: bucket 은 누적값 (counter). rate 으로 감싸야 의미 있는 ratio.
**Q4**: rate 는 range 의 평균 (smooth). irate 는 마지막 2 샘플 (즉각, 노이즈 ↑).
**Q5**: Rate (RPS), Errors (에러율), Duration (응답 시간) — 서비스 헬스 3축
**Q6**: 비싼 쿼리 미리 계산 → 대시보드/alert 빠름. 비용: 추가 시계열 + CPU 평가.
**Q7**: 여러 Pod 의 quantile 을 합산 못 함 (수학적). Histogram 으로 하면 bucket 합산 후 quantile 계산 가능.
**Q8**: 전자는 모든 라벨 합쳐 단일 값. 후자는 pod 별로 분리.
**Q9**: 5분 동안 조건 만족하면 Firing (일시적 spike 무시).
**Q10**: `topk(5, sum by (service) (rate(http_requests_total{status=~"5.."}[5m])))`

</details>

다음: [pitfalls.md](./pitfalls.md)
