# Lab 01 — 자주 쓰는 PromQL 패턴

> **🌱 핵심 개념 미리보기**
> - **RED 메서드**: **R**ate(요청률) + **E**rrors(에러율) + **D**uration(지연) — 서비스 SLI 의 표준
> - **USE 메서드**: **U**tilization(사용률) + **S**aturation(포화도) + **E**rrors(에러) — 자원 (CPU, 메모리) 분석용
> - **Counter**: 단조 증가 (`*_total`). 직접 보면 무의미, `rate()` 로 변화율 추출
> - **Gauge**: 위아래 변동 (현재 메모리, 큐 길이). 직접 봄
> - **Histogram**: bucket + `_count` + `_sum`. `histogram_quantile()` 로 분위수 (p50/p95/p99)
> - **Vector matching**: 두 메트릭 연산 시 라벨 매칭 규칙 (`on`, `ignoring`, `group_left`)
>
> **PromQL 첫 직관**:
> ```
>   메트릭_이름{라벨필터}[시간윈도우]   ← Counter 의 raw
>   rate(메트릭_이름[1m])                ← 초당 변화율 (RPS, MBps)
>   sum by (라벨) (위)                   ← 그 라벨 단위로 합산
> ```

## 1. RED — 서비스 레벨 (order-service 사용)

### 1.1 Rate (RPS)
```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
```

http://localhost:9090 에서:
```promql
# 클러스터 전체 HTTP RPS
sum(rate(gin_request_duration_seconds_count[1m]))

# 서비스 별
sum by (service) (rate(gin_request_duration_seconds_count[1m]))
```

> **🧠 `rate(...[1m])` 의 정확한 의미**
> "지난 1분간 초당 평균 변화량".
> Counter 가 1000 → 1300 으로 1분간 증가했다면 `rate(...[1m]) = 5/s` (300/60).
>
> **함정 — `[range]` 가 너무 짧으면**:
> - scrape interval 이 30s 인데 `rate(...[30s])` 하면 데이터 포인트 1개 → 계산 불가 → NaN
> - 권장: `range >= 4 × scrape_interval` (interval 30s 면 최소 [2m])
>
> **`rate` vs `irate`**:
> - `rate`: 윈도우 내 평균 (smooth, 그래프용)
> - `irate`: 마지막 두 점만 (즉시 반응, 알람용)

### 1.2 Errors
```promql
# 5xx 비율
sum by (service) (rate(gin_request_duration_seconds_count{code=~"5.."}[1m]))
  /
sum by (service) (rate(gin_request_duration_seconds_count[1m]))
```

> **🧠 비율 계산 시 주의**
> 분자/분모를 **같은 라벨 set** 으로 맞춰야 vector matching 이 자동 작동.
> 위 쿼리는 둘 다 `sum by (service)` → `service` 라벨만 남음 → 매칭 OK.
>
> **흔한 실수**:
> ```promql
> rate(req{code=~"5.."}[1m]) / rate(req[1m])
> ```
> 분자에 `code` 라벨 남아있고 분모엔 없음 → 매칭 실패 → 결과 비어있음.
>
> **0으로 나누기**: 분모가 0 (요청 없음) 이면 결과 NaN. Grafana 에서 `OR vector(0)` 로 fallback.

### 1.3 Duration (Histogram p99)
```promql
histogram_quantile(0.99,
  sum by (le, path) (rate(gin_request_duration_seconds_bucket[5m]))
)
```

> Module 21 에서 Go 앱에 직접 메트릭을 추가하면 위 메트릭들이 실제로 채워집니다. 본 lab 에서는 메트릭 이름이 환경마다 다를 수 있어 가짜 데이터로 시연 가능.

> **🧠 `histogram_quantile` 의 3단 구조**
> ```
>   1. _bucket 메트릭에 rate() — Counter 라 변화율 필요
>   2. sum by (le, ...) — le 는 반드시 보존 (bucket 경계값)
>   3. histogram_quantile(0.99, ...) — bucket 분포에서 분위수 계산
> ```
>
> **`le` 라벨이 핵심** — "less than or equal" = bucket 의 상한.
> 예: `bucket{le="0.1"} = 950` = "100ms 이하 응답이 950건".
>
> `le` 빼고 sum 하면 분포 정보 소실 → quantile 계산 불가.
>
> **p99 의 해석**: "100건 중 99건은 이 값 이하". p99=200ms = "1% 의 사용자가 200ms 이상 경험".

## 2. USE — 자원 레벨

### 2.1 CPU
```promql
# 노드 CPU 사용률 (%)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)

# 컨테이너 CPU
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="order"}[1m]))
```

> **🧠 왜 CPU 는 "100 - idle" 로 구하나?**
> `node_cpu_seconds_total` 은 mode 별로 누적 시간 기록 (`idle`, `user`, `system`, `iowait`, `irq`...).
> 각 코어당 1초마다 1초 누적되므로 비율로 변환:
> - `rate(...{mode="idle"}[1m])` = 1초 중 idle 비율 (0~1)
> - `1 - idle 비율` = 사용 비율
> - `× 100` = %
>
> **컨테이너 CPU 단위**: `container_cpu_usage_seconds_total` 은 **CPU초** 단위. rate 결과 = vCPU 코어 수 (0.5 = 0.5코어).

### 2.2 Memory
```promql
# 노드 메모리 사용률
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# 컨테이너 메모리
sum by (pod) (container_memory_working_set_bytes{namespace="order"})
```

> **🧠 `MemAvailable` vs `MemFree` 의 차이 (리눅스)**
> - **`MemFree`**: 정말 안 쓰는 메모리 (보통 적음)
> - **`MemAvailable`**: 캐시 회수 가능 포함 = "실질적으로 쓸 수 있는 메모리"
>
> 메모리 사용률은 **항상 `MemAvailable` 기준**. `MemFree` 로 계산하면 "사용률 99%" 처럼 보이지만 실제론 페이지캐시.
>
> **컨테이너 메모리 — `working_set_bytes`** = OOM Killer 가 보는 값. RSS + 일부 anonymous. limits.memory 와 비교 시 이 값.

### 2.3 Network
```promql
# Pod 별 수신 bytes/s
sum by (pod) (rate(container_network_receive_bytes_total{namespace="order"}[1m]))
```

## 3. 자주 쓰는 추가 패턴

### 3.1 Pod 재시작 횟수
```promql
sum by (namespace, pod) (kube_pod_container_status_restarts_total)
```

> **🧠 재시작 알람 패턴**
> 위는 누적 횟수. "최근 1시간 내 재시작 발생" 알람:
> ```promql
> increase(kube_pod_container_status_restarts_total[1h]) > 0
> ```
> `increase` = `rate × 시간` = 윈도우 내 총 증가량.

### 3.2 Top N (가장 비싼 5개)
```promql
topk(5, sum by (pod) (rate(container_cpu_usage_seconds_total[1m])))
```

### 3.3 노드별 Pod 수
```promql
count by (node) (kube_pod_info)
```

### 3.4 Container resource utilization
```promql
# CPU usage / requests
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="order"}[1m]))
  /
sum by (pod) (kube_pod_container_resource_requests{namespace="order",resource="cpu"})
```

이 비율이 0.5 미만이면 over-provisioning → Module 17 의 right-sizing.

> **🧠 utilization vs saturation**
> - **Utilization**: 실제 사용 / 할당 (위 쿼리, 0~1)
> - **Saturation**: 한계 초과 시도 (CPU throttling, OOM 직전, 큐 길이)
>
> CPU saturation: `container_cpu_cfs_throttled_periods_total` (CFS 가 throttle 한 횟수).
> 이게 0 이 아니면 = limits.cpu 가 너무 빡빡 (실제 더 쓰고 싶은데 못 씀).

## 4. Vector Matching 시연

```promql
# 두 메트릭이 다른 라벨 set 일 때
sum by (pod) (rate(container_cpu_usage_seconds_total[1m]))
  / on(pod)
sum by (pod) (kube_pod_container_resource_limits{resource="cpu"})
```

라벨 set 이 정확히 같으면 자동 매칭. 안 맞으면:
- `on(label1, label2)` — 명시 매칭
- `ignoring(label)` — 그 라벨 무시
- `group_left` / `group_right` — many-to-one

> **🧠 vector matching 결정 트리**
> ```
>   라벨 set 동일?
>     ├─ Yes → 자동 매칭 (1:1)
>     └─ No → 다음 질문
>          ├─ 일부 라벨만 매칭? → on(...) / ignoring(...)
>          └─ 한 쪽이 N개 vs 다른 쪽 1개? → group_left / group_right
> ```
>
> **`group_left` 의 전형적 패턴** — Pod 메트릭에 Deployment 정보 붙이기:
> ```promql
> rate(http_requests_total[1m])
>   * on(pod) group_left(deployment)
> kube_pod_owner
> ```
> = 각 Pod 의 RPS 에 그 Pod 의 deployment 라벨을 추가.

## 5. subquery 시연

```promql
# 지난 1시간 동안의 RPS 의 max
max_over_time(
  sum(rate(gin_request_duration_seconds_count[1m]))[1h:1m]
)
```

`[1h:1m]` — 1분 step 으로 1시간 평가.

> **🧠 subquery `[range:step]` 의 동작**
> 일반 `metric[range]` 는 raw 데이터 윈도우.
> `(expr)[range:step]` 는 **expr 를 step 마다 재평가** 하여 그 결과를 range 동안 모음.
>
> 위 예: `sum(rate(...[1m]))` 를 1분마다 60번 평가 → 그 60개 값에서 max.
>
> **비용 주의**: subquery 는 매우 느림. range × (range/step) 만큼 평가.
> 자주 쓰는 패턴이면 recording rule 로 사전 계산 (다음 lab).

## 6. 안티패턴 시연

다음 쿼리들이 왜 잘못됐는지 직접 실행해 결과 확인:

### 6.1 Counter 에 rate 안 감기
```promql
http_requests_total
```
→ 누적값. 시각화 의미 없음.

> **🧠 Counter 가 이상해 보이는 이유**
> Counter 는 항상 우상향 (Pod 재시작 시 0 으로 리셋). 그래프로 보면 "계속 올라가는 직선" → 정보 없음.
>
> rate 가 진짜 정보 추출:
> - rate=0 → 활동 없음
> - rate=10 → 초당 10건
> - rate 갑자기 0 → 트래픽 끊김 (알람!)

### 6.2 Histogram bucket 에 rate 안 감기
```promql
histogram_quantile(0.99, gin_request_duration_seconds_bucket)
```
→ 누적이라 quantile 결과가 누적 잡음. rate 필수.

### 6.3 sum 에 by 누락
```promql
sum(rate(gin_request_duration_seconds_count[1m]))
```
→ 모든 라벨 합쳐져 단일 값. 어느 서비스 / Pod 인지 모름.

올바른 쿼리:
```promql
sum by (service) (rate(gin_request_duration_seconds_count[1m]))
```

> **🧠 `by` vs `without` 의 선택**
> - **`by (a, b)`**: a, b 만 유지하고 나머지 합산 → "이 라벨로만 보고 싶다" (whitelist)
> - **`without (a, b)`**: a, b 만 제거하고 나머지 유지 → "이 라벨만 무시" (blacklist)
>
> 라벨 종류가 많을 때 (예: K8s 메트릭) `without (instance, pod)` 가 더 유연.
> 단순 SLI 는 `by (service)` 가 명확.

## 학습 확인

1. `rate(gauge[5m])` 가 의미 없는 이유?
2. Histogram 의 `le` 라벨이 cardinality 에 미치는 영향?
3. Summary 메트릭의 한계 (분산 환경에서)?

> **힌트**:
> 1. rate 는 단조 증가 가정 (Counter 전용). Gauge 는 감소 가능 → 음수 결과 가능 → 오해. Gauge 변화율은 `deriv()` 사용.
> 2. bucket 수만큼 시계열 곱셈. bucket 10개 + Inf + _count + _sum = 12배. 라벨 조합도 같이 곱해짐.
> 3. Summary 는 분위수를 클라이언트가 미리 계산 → 다른 인스턴스끼리 합산 불가 (p99 의 평균 ≠ 전체 p99). Histogram 은 bucket 합산 가능.

다음: [lab-02-recording-rules.md](./lab-02-recording-rules.md)
