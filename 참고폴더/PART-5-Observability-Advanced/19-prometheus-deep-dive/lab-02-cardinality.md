# Lab 02 — Cardinality 폭발 시연 + 진단

> **🌱 Cardinality 가 뭔가? 왜 위험한가?**
> **Cardinality** = 한 메트릭의 라벨 조합 수 = 시계열 수.
> 예: `http_requests_total{method, code, path}` 에서 method 5종 × code 10종 × path 100종 = 5,000 시계열.
>
> **위험한 이유**:
> - Prometheus 메모리: head series 1개당 ~3KiB → 100만 시계열 = 3 GiB
> - 디스크: 시계열마다 별도 파일 → IOPS 폭증
> - 쿼리 속도: PromQL 이 모든 매칭 시계열을 메모리에 로드 → OOM
>
> **고-cardinality 라벨의 전형적 함정**:
> - `user_id`, `email`, `request_id`, `trace_id` (값이 무한)
> - `timestamp`, `pod_name` (재생성마다 변함)
> - `path` (동적 라우팅: `/users/123`, `/users/124`...)

## 학습 확인 포인트

- [ ] cardinality 가 어떻게 폭증하는지 직접 봄
- [ ] Prometheus 의 cardinality 분석 도구 사용
- [ ] metric_relabel 로 라벨 drop 해서 줄이기

## 1. Top cardinality 확인 (베이스라인)

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=topk(10, count by (__name__)({__name__=~".+"}))' \
  | jq -r '.data.result[] | "\(.metric.__name__)\t\(.value[1])"' \
  | sort -k2 -nr
```

기대 (예시):
```
apiserver_request_duration_seconds_bucket    8500   ← histogram 의 bucket 별
container_network_receive_bytes_total        2400
kubelet_runtime_operations_duration_seconds_bucket  2000
...
```

> **🧠 왜 `*_bucket` 이 항상 1위인가?**
> Histogram 메트릭은 자동으로 **여러 bucket 시계열 + `_count` + `_sum`** 을 만듦.
> 예: `apiserver_request_duration_seconds` 가 라벨 조합 100개 + bucket 10개 = **시계열 1,200개** (100 × (10+2)).
>
> bucket 수는 `histogram` 정의의 `Buckets:` 배열 길이. 기본값 11개 + Inf = 12개.
> → Histogram 1개 추가 = 단순 Counter 12배의 cardinality 비용.

## 2. 라벨 카운트

```bash
curl -sG http://localhost:9090/api/v1/labels | jq '.data | length'
```

→ 클러스터 전체에서 사용되는 라벨 종류 수.

> **🧠 라벨 종류 수 vs 라벨 값 수**
> - **라벨 종류 (이름) 수** = 위 명령 결과. 보통 100~300 (관리 가능).
> - **라벨 값 수** = 같은 라벨에 들어간 unique value 개수. 이게 폭발의 주범.
>
> 예: 라벨 이름 `pod` (1개) 인데 값은 노드 재생성마다 바뀜 → 1주에 10,000 unique → cardinality 폭발.

## 3. 의도적 cardinality 폭발

라벨 값에 timestamp 같은 고유 값 넣으면 시계열 폭증:

```bash
# Counter 메트릭에 user_id 라벨을 1만 개 다른 값으로
kubectl run cardinality-bomb -n order --image=alpine --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"c","image":"alpine","command":["sh","-c"],"args":["apk add -q curl && for i in $(seq 1 5000); do curl -s -X POST http://order-service/orders -H Content-Type:application/json -d {\"user_id\":\"u-'$i'\",\"amount\":1} > /dev/null; done; sleep 600"]}]}}'
```

15분 정도 두면 order-service 가 user_id 별로 메트릭을 노출 (만약 `user_id` 가 라벨에 들어간다면 — 본 lab 의 order-service 는 이미 적절히 짜여 있어서 user_id 를 라벨로 안 씀. 이건 가상 시나리오 시뮬레이션.).

> **🧠 왜 user_id 를 라벨로 안 쓰는 게 정답인가?**
> "유저별 RPS 알고 싶다" → 메트릭 라벨에 user_id 넣고 싶음. 함정.
> - 유저 100만 명 = 시계열 100만개 = Prometheus OOM
> - 어차피 그 데이터는 **로그/Trace** 에 있음 (메트릭은 통계용)
>
> **올바른 방법**:
> - 메트릭은 **집계** 차원만 (method, status, endpoint group)
> - 개별 유저 분석은 로그 (CloudWatch / Loki) 또는 분산 trace (X-Ray / Tempo)
> - "이 유저만 느림" = trace_id 로 확인, 메트릭 X

**더 직접적인 시뮬레이션** — Prometheus 가 내부에 만든 라벨 폭주 측정:

```bash
# 모든 Pod가 만들어내는 시계열 수 추이
curl -sG http://localhost:9090/api/v1/query --data-urlencode 'query=prometheus_tsdb_head_series'
```

## 4. cardinality 진단 명령

### 4.1 메트릭 별 시계열 수
```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=topk(15, count by (__name__)({__name__=~".+"}))' \
  | jq -r '.data.result[] | "\(.value[1])\t\(.metric.__name__)"' | sort -k1 -nr
```

> **🧠 `topk(15, ...)` 의 의미**
> PromQL 의 `topk(N, expr)` = expr 결과 중 상위 N개 시계열 반환.
> cardinality 진단의 첫 명령 — "어느 메트릭이 가장 많은 시계열을 만드는지" 즉시 파악.
> 보통 상위 10개가 전체의 50~80% 차지.

### 4.2 라벨 별 unique value 수
```bash
for label in pod namespace container job instance method status code; do
  COUNT=$(curl -sG http://localhost:9090/api/v1/label/${label}/values \
    | jq '.data | length')
  echo "$label: $COUNT"
done
```

> **🧠 이 결과의 해석법**
> - `pod`, `instance`: 노드/Pod 재생성으로 누적 — 자연스러움 (TSDB 가 옛 시계열 retention 후 정리)
> - `method`, `status`, `code`: 작은 수 (5~20) 기대 — 비정상 크면 잘못 라벨링
> - `path`, `url`, `endpoint`: 100+ 면 위험 신호 — 동적 라우팅이 라벨로 들어감
> - `user_id`, `request_id`, `trace_id`: 절대 보이면 안 됨 (있으면 즉시 drop)

### 4.3 특정 메트릭의 라벨 조합 분포
```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=count by (pod)({__name__="container_cpu_usage_seconds_total",namespace="order"})'
```

## 5. metric_relabel 로 cardinality 절감

ServiceMonitor 에 relabel 추가:
```yaml
spec:
  endpoints:
    - port: metrics
      metricRelabelings:
        # go_gc_* 시리즈 모두 drop
        - sourceLabels: [__name__]
          regex: 'go_gc_.+'
          action: drop

        # 특정 라벨 제거
        - regex: 'pod_template_hash'
          action: labeldrop
```

> **🧠 `relabelings` vs `metricRelabelings` 의 차이**
> - **`relabelings`**: scrape **전** 동작. target SD 라벨 (`__meta_*`) 가공. target 자체를 drop 가능.
> - **`metricRelabelings`**: scrape **후** 동작. 받은 메트릭마다 적용. 메트릭 단위 drop / 라벨 제거.
>
> cardinality 절감은 거의 항상 `metricRelabelings`. (이미 받은 메트릭에서 골라내기)
>
> **action 종류**:
> | action | 효과 |
> |--------|------|
> | `keep` | regex 매칭만 유지 (나머지 drop) |
> | `drop` | regex 매칭만 drop |
> | `labeldrop` | 라벨 이름 매칭하면 그 라벨만 제거 (시계열 자체는 유지) |
> | `labelkeep` | 매칭 라벨만 유지 |
> | `replace` | 라벨 값 변환 (기본값) |
>
> **흔한 패턴**:
> ```yaml
> # 응답 시간 histogram 의 bucket 줄이기 (수가 많은 bucket drop)
> - sourceLabels: [__name__, le]
>   regex: 'http_request_duration_seconds_bucket;(0\.005|0\.01|0\.025|...)'
>   action: drop
> ```

## 6. /api/v1/admin/tsdb/delete (위험 — 학습용만)

특정 시계열 영구 삭제 (--web.enable-admin-api 필요):
```bash
# 활성화 옵션이면:
curl -X POST 'http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]=high_cardinality_metric'
```

→ 기본 비활성. 학습 환경에서 특정 시리즈가 디스크 잡아먹으면 사용 가능. 운영은 신중.

> **🧠 왜 운영에서 신중한가?**
> 1. **삭제는 "마킹" 만** — 실제 디스크 회수는 다음 compaction (수 시간 후)
> 2. **정규식 오타** = 의도치 않은 메트릭 대량 삭제 (롤백 불가)
> 3. **알람 의존성** — 그 메트릭에 걸린 알람이 evaluation 실패
>
> **운영 대안**:
> - 새로 들어오는 cardinality 만 막기 (relabel drop) — 안전
> - 짧은 retention 설정 후 자연 만료 대기

## 7. 정리

```bash
kubectl delete pod -n order cardinality-bomb --ignore-not-found
```

## 학습 확인

1. cardinality 가 메모리/디스크에 미치는 정확한 영향은?
2. 라벨에 user_id 넣으면 안 되는 이유는?
3. histogram 의 `le` 라벨이 cardinality 에 미치는 영향은?

> **힌트**:
> 1. 메모리 = head series × ~3KiB (선형). 디스크 = 시계열마다 chunk 파일 → IOPS 증가 + 압축률 감소.
> 2. 유저 수 = 라벨 unique 값 = 시계열 수 → OOM. 또한 본질적으로 메트릭이 아닌 trace/log 의 영역.
> 3. histogram 1개 = bucket 수만큼 시계열 (보통 12개). bucket 추가는 곱셈으로 늘어남.

다음: [lab-03-federation.md](./lab-03-federation.md)
