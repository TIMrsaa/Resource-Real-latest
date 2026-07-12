# Lab 01 — Scrape 동작 직접 분석

> **🌱 핵심 개념 미리보기**
> - **Scrape**: Prometheus 가 주기적으로 (기본 30s) target 의 `/metrics` 를 HTTP GET 으로 긁어가는 동작
> - **Target**: scrape 대상 endpoint (Pod IP:port + path). ServiceMonitor / 정적 설정으로 등록
> - **Service Discovery (SD)**: K8s API 를 watch 해서 target 자동 발견. 라벨 (`__meta_kubernetes_*`) 자동 부여
> - **Relabel**: SD 로 발견한 raw 라벨을 가공/필터링해서 최종 시계열의 라벨로 변환
> - **시계열 (time series)**: `metric{label1="v1",label2="v2"}` 라벨 조합 1개당 1개 시계열
>
> **scrape 한 번 흐름**:
> ```
>   K8s API → SD가 Pod 발견 → __meta_* 라벨 부여
>   → relabel 규칙 적용 → 최종 라벨 결정
>   → Prometheus가 HTTP GET /metrics
>   → 응답 파싱 → TSDB 저장
> ```

## 1. Prometheus 의 targets 페이지

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
```

브라우저: http://localhost:9090/targets

각 target 의 정보:
- **State** — UP / DOWN
- **Endpoint** — `http://10.20.x.y:9090/metrics`
- **Last Scrape** — 마지막 scrape 시각
- **Scrape Duration** — 응답 시간
- **Labels** — 자동 부여된 라벨 (job, instance, pod, namespace 등)

> **🧠 State 가 DOWN 이면 어디부터 봐야?**
> 1. **Endpoint URL 직접 호출 가능?** — 디버그 Pod 로 `curl http://<ip>:<port>/metrics`
> 2. **DNS / NetworkPolicy** — Prometheus Pod 가 그 IP 에 닿을 수 있나
> 3. **응답 파싱 에러** — 메트릭 포맷 (텍스트 노출 형식) 위반
> 4. **scrape timeout** — 응답이 너무 느림
>
> Prometheus UI 의 target 행을 클릭하면 마지막 에러 메시지가 보임 (`Error scraping target: ...`).

## 2. CLI 로 target 정보

```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[0]'
```

기대 (예시):
```json
{
  "discoveredLabels": {
    "__address__": "10.20.1.5:9090",
    "__meta_kubernetes_pod_name": "order-service-xxx",
    "__meta_kubernetes_namespace": "order"
  },
  "labels": {
    "namespace": "order",
    "pod": "order-service-xxx",
    "job": "order-msa"
  },
  "scrapePool": "serviceMonitor/monitoring/order-msa/0",
  "scrapeUrl": "http://10.20.1.5:9090/metrics",
  "lastScrape": "...",
  "lastScrapeDuration": 0.012,
  "health": "up"
}
```

`discoveredLabels` (`__meta_*`) 는 SD 결과 → relabel 후 `labels` 만 남음.

> **🧠 `__meta_*` vs 최종 `labels` 의 차이**
> - **`__meta_*`** (언더스코어 2개로 시작) = SD 가 K8s API 에서 가져온 raw 정보. **저장되지 않음**.
> - **최종 `labels`** = relabel 규칙이 `__meta_*` 를 가공해 만든 결과. **TSDB 에 저장됨**.
>
> 왜 분리? — K8s 메타데이터는 너무 많고 cardinality 폭발 위험. 필요한 것만 골라 보존하기 위해.
>
> **자주 쓰는 relabel 패턴**:
> ```yaml
> - sourceLabels: [__meta_kubernetes_pod_label_app]
>   targetLabel: app          # Pod의 app 라벨을 메트릭 라벨로 승격
> - sourceLabels: [__meta_kubernetes_namespace]
>   targetLabel: namespace
> ```

## 3. /metrics 직접 호출

```bash
kubectl run -it --rm dbg --image=alpine -n order -- sh -c "
  apk add -q curl
  curl -s http://order-service:9090/metrics | head -30
"
```

기대:
```
# HELP go_goroutines Number of goroutines
# TYPE go_goroutines gauge
go_goroutines 8

# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{code="200",method="POST",path="/orders"} 12345
...
```

각 메트릭은 `# HELP` + `# TYPE` 헤더 + 샘플(들).

> **🧠 Prometheus 텍스트 노출 형식 (Exposition Format)**
> 사람이 읽기 쉬운 plain text. 한 줄 = 한 샘플.
> ```
>   # HELP <metric>  <설명>
>   # TYPE <metric>  counter|gauge|histogram|summary
>   <metric>{label="v"} <값> [<timestamp>]
> ```
> - **HELP**: 사람용 설명 (Grafana 의 metric 설명에 표시됨)
> - **TYPE**: PromQL 함수 선택 (Counter는 `rate()`, Gauge는 직접)
> - **타임스탬프** 생략 시 = scrape 시점 자동 부여
>
> 이 텍스트만 노출하면 어떤 언어로든 메트릭 익스포트 가능 (= Prometheus 생태계의 핵심).

## 4. 한 메트릭의 시계열 수

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=count by (__name__)({__name__="http_requests_total"})' \
  | jq '.data.result[0].value[1]'
```

→ 그 메트릭 이름의 라벨 조합 수 = 시계열 수.

> **🧠 "메트릭 1개" vs "시계열 N 개" 의 결정적 구분**
> ```
>   http_requests_total{method="GET", code="200"}  ← 시계열 1
>   http_requests_total{method="POST",code="200"}  ← 시계열 2
>   http_requests_total{method="GET", code="500"}  ← 시계열 3
> ```
> = 메트릭 이름은 1개 (`http_requests_total`), 시계열은 라벨 조합 수만큼.
>
> Prometheus 의 메모리/디스크 비용은 **메트릭 개수가 아니라 시계열 개수**에 비례.
> 라벨 추가는 곱셈으로 늘어남: `methods(5) × codes(10) × paths(50) = 2500 시계열`.

## 5. 전체 시계열 수

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=count({__name__=~".+"})' \
  | jq -r '.data.result[0].value[1]'
```

학습 클러스터면 보통 5,000 ~ 50,000.

> **🧠 시계열 수의 운영 임계값 (대략)**
> | 시계열 수 | Prometheus 메모리 (대략) | 권고 |
> |----------|------------------------|------|
> | < 100K | 2~4 GiB | 단일 인스턴스 OK |
> | 100K ~ 1M | 8~16 GiB | recording rule 검토 |
> | 1M ~ 10M | 32 GiB+ | Thanos / Mimir / AMP |
> | 10M+ | 단일로 불가 | 샤딩 + 원격 저장소 필수 |
>
> 1 시계열 ≈ 3~5 KiB 메모리 (head chunks 포함). Lab 02 에서 이 임계값 넘기는 시연.

## 6. TSDB 상태 (Prometheus UI)

http://localhost:9090/tsdb-status

표시되는 정보:
- Number of series
- Top label names by series count
- Top metric names by series count
- Memory chunks 등

> **🧠 TSDB 구조 — head chunks vs persistent blocks**
> - **Head**: 최근 ~2시간의 데이터, 메모리에 보관 (빠른 쓰기/읽기)
> - **Block**: 2시간마다 head 가 디스크 block 으로 flush. 압축 (보통 10~30x).
> - **WAL** (Write-Ahead Log): head 가 죽어도 복구 가능하게 디스크에 미리 기록
>
> 즉 **메모리 사용량 ≈ head series × ~3KiB**, 디스크 사용량 ≈ 압축된 block.
> tsdb-status 의 `Number of series` 가 head series. 이게 메모리 추정의 1차 지표.

## 7. ServiceMonitor 의 selector 매칭 디버그

```bash
# Prometheus 의 selector 확인
kubectl get prometheus -n monitoring -o yaml | yq '.items[].spec.serviceMonitorSelector'

# 내 ServiceMonitor 의 라벨
kubectl get servicemonitor -n monitoring order-msa -o yaml | yq '.metadata.labels'
```

매칭 안 되면 `release: kps` 라벨 추가.

> **🧠 매칭 디버깅 3단 체크리스트**
> ServiceMonitor 만들었는데 /targets 에 안 나타날 때:
> 1. **ServiceMonitor 라벨** ↔ **Prometheus.spec.serviceMonitorSelector** 매칭? (`release: kps` 가 흔한 함정)
> 2. **ServiceMonitor.spec.selector** ↔ **Service.metadata.labels** 매칭? (selector 오타)
> 3. **Service.spec.ports.name** ↔ **ServiceMonitor.spec.endpoints[].port** 매칭? (포트 이름 일치 필수)
>
> 이 셋 중 하나라도 어긋나면 sliently 무시. 에러 로그도 안 남음 (Operator 가 그냥 패스).

## 8. scrape interval / timeout 변경

ServiceMonitor:
```yaml
endpoints:
  - port: metrics
    interval: 15s
    scrapeTimeout: 10s     # interval 보다 짧아야
```

너무 짧으면 — Prometheus 부하 ↑, 너무 길면 — 일시 spike 놓침.

> **🧠 interval 선택 가이드**
> | 메트릭 종류 | 권장 interval | 이유 |
> |------------|--------------|------|
> | 노드 시스템 (CPU, RAM) | 15~30s | 빠른 변화, 알람 반응속도 중요 |
> | 앱 요청률 (RPS) | 15s | rate() 정확도 |
> | 비즈니스 메트릭 (DAU 등) | 60s ~ 5m | 천천히 변함 |
> | 배치 작업 결과 | Pushgateway / 1m+ | scrape 미스 위험 |
>
> **`scrapeTimeout < interval`** 필수. 어기면 Prometheus 가 거부 (config 에러).
> rate() 함수는 `[range]` 가 interval 의 4배 이상이어야 신뢰 가능 → `interval=15s` 면 `rate(...[1m])` 최소.

## 학습 확인

1. `__meta_*` 라벨이 최종 메트릭에 안 남는 이유는?
2. 같은 Pod 의 metrics endpoint 가 여러 개라면 어떻게 노출?
3. scrape_timeout > interval 이면 어떤 일이?

> **힌트**:
> 1. cardinality 보호 + K8s 메타가 너무 많음. relabel 로 필요한 것만 승격.
> 2. ServiceMonitor 의 `endpoints` 배열에 여러 포트 등록. 또는 PodMonitor 로 Pod 직접 지정.
> 3. Operator 가 config 검증에서 거부 (Prometheus reload 실패). 해석상 한 scrape 가 다음 interval 까지 안 끝나면 누락 발생.

다음: [lab-02-cardinality.md](./lab-02-cardinality.md)
