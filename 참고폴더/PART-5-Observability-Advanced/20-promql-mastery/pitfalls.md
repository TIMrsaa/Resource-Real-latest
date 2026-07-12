# 흔한 함정 5선 — 20. PromQL Mastery

## 1. Counter 의 누적값을 그대로 시각화

**증상**: 그래프가 단조 증가하기만 함. "RPS" 라고 라벨 붙인 패널이 사실은 누적 수.

**원인**: `rate(...)` 안 감싸고 metric name 만.

**해결**:
```promql
# 잘못
http_requests_total

# 올바름
rate(http_requests_total[1m])
```

---

## 2. histogram_quantile 의 잘못된 사용

**증상**: 99th percentile latency 가 비현실적 (예: 5초)

**원인 후보**:
- `rate` 안 감기
- `le` 라벨 빠뜨리고 sum
- `_bucket` 메트릭 아닌 `_sum` 또는 `_count` 사용

**해결**:
```promql
# 표준 형식
histogram_quantile(0.99,
  sum by (le, ...other labels) (
    rate(<metric>_bucket[5m])
  )
)
```

`le` 는 무조건 group by 에 포함.

---

## 3. recording rule 이름 오타로 alert 가 evaluate 안 됨

**증상**: alert 가 `Inactive` 인데 실제 조건은 만족.

**원인**: alert expr 의 record name 오타 → 매칭 시계열 없음 → 0 으로 평가.

**진단**:
```bash
# 그 record 가 실제 존재하는지
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=namespace:http_error_rate:ratio'
```

빈 결과면 record 미생성.

---

## 4. interval 너무 짧아 evaluation cost 폭증

**증상**: Prometheus CPU 사용률이 점점 올라감.

**원인**: recording rule 의 `interval: 5s` 같이 짧게 + 비싼 쿼리.

**해결**:
- 일반 rule 은 30s 또는 1m
- 매우 비싼 쿼리는 5m 도 OK
- evaluation 시간 모니터: `prometheus_rule_evaluation_duration_seconds`

---

## 5. Vector matching 에러

**증상**: PromQL 결과 비어있음. 로그에 `many-to-many matching not allowed`.

**원인**: 양쪽 vector 의 라벨 set 이 다른데 자동 매칭 시도.

**해결**:
```promql
# CPU usage / requests 비율
sum by (pod) (rate(container_cpu_usage_seconds_total[1m]))
  / on(pod) group_left
sum by (pod) (kube_pod_container_resource_requests{resource="cpu"})
```

`on(pod)` — 매칭 라벨 명시.
`group_left` — 왼쪽이 더 많은 라벨을 가짐 (one-to-many).
