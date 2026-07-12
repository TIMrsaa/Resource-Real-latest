# PromQL 치트시트 (Part 5 실전 모음)

> (모듈 번호) = 배운 곳. 03의 대원칙: counter는 rate로, 분포는 분위수로, 라벨은 유한하게.

## 기본 패턴

```promql
# 요청율 (03·08)
sum(rate(http_requests_total[5m]))
sum by (service) (rate(http_requests_total[5m]))              # 서비스별

# 에러 비율 — 개수 아니라 비율! (09)
sum(rate(http_requests_total{code=~"5.."}[5m]))
  / sum(rate(http_requests_total[5m]))

# 분위수 (03 — histogram)
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
# 다중 서비스: sum by (le, service) (...)

# 지연 SLI — "임계 이내 비율" 형태 (21)
sum(rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))
  / sum(rate(http_request_duration_seconds_count[5m]))

# 구간 증가량
increase(http_requests_total[1h])
```

## "없음"의 감지 (08·10 — 조용한 실패의 해독제)

```promql
up == 0                          # 스크레이프 실패
absent(up{job="payment"})        # 타깃 자체가 사라짐
absent(slo:error_ratio:rate5m)   # recording rule 미평가
```

## 플랫폼 조사 (05·08 — 3대장 구분!)

```promql
# KSM(오브젝트 상태)
kube_pod_status_phase{phase="Pending"} > 0
increase(kube_pod_container_status_restarts_total[1h]) > 3
kube_deployment_status_replicas_available < kube_deployment_spec_replicas

# cAdvisor(컨테이너 사용량)
sum by (pod) (rate(container_cpu_usage_seconds_total[5m]))
container_memory_working_set_bytes / on(pod,container)
  kube_pod_container_resource_limits{resource="memory"}       # OOM 임박

# node-exporter(기계)
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))
predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0   # 고갈 예측

# 포화 — 사용률보다 진짜 신호 (09)
rate(container_cpu_cfs_throttled_periods_total[5m])
  / rate(container_cpu_cfs_periods_total[5m])                 # CPU 스로틀
```

## SLO·번레이트 (21)

```promql
# recording rules 계층 (창별)
# slo:payment_error_ratio:rate5m / rate1h / rate6h ...

# page: 빠른 소진 (멀티윈도우 AND)
slo:err:rate1h > 14.4 * (1 - 0.999)
  and slo:err:rate5m > 14.4 * (1 - 0.999)
# ticket: 느린 누수
slo:err:rate6h > 3 * (1 - 0.999)
  and slo:err:rate30m > 3 * (1 - 0.999)

# 버짓 사용률
sum(increase(errors_total[30d])) / ((1 - 0.999) * sum(increase(requests_total[30d])))
```

## 관측의 관측 (22 — 자기 계측)

```promql
prometheus_tsdb_head_series                                    # 시계열 총량 (03 폭발 감시)
topk(10, count by (__name__)({__name__=~".+"}))                # 뚱뚱한 메트릭 순위
scrape_samples_scraped                                         # 타깃별 (폭발 조기 발견)
rate(fluentbit_output_dropped_records_total[5m]) > 0           # 로그 유실! (06)
rate(prometheus_remote_storage_samples_failed_total[5m])       # AMP행 실패 (14)
prometheus_tsdb_head_series > 1.5 * (prometheus_tsdb_head_series offset 1h)  # 급증
```

## 조인 (08 — 라벨 매칭)

```promql
# 사용량(cAdvisor)에 메타(KSM 라벨)를 붙이기
sum by (pod) (rate(container_cpu_usage_seconds_total[5m]))
  * on(pod) group_left(label_team) kube_pod_labels
```

## 함정 리마인더

- counter 원값 플롯 금지 → rate() / gauge에 rate 금지 (03)
- 평균 지연 금지 → 분위수 / 에러 개수 금지 → 비율 (09)
- 알림은 인스턴스가 아니라 집계(sum by service) 위에 (10)
- rate 창은 scrape 간격의 4배 이상 (08)
- 정의는 recording rule로 단일화 — 복붙은 분기의 시작 (08)
