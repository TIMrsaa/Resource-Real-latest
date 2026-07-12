# 이론 — Prometheus 아키텍처

> **🌱 Prometheus = "우체부가 집집마다 우편함 확인"**
> Push 시스템이 *주민이 우체국에 편지 보내기* 라면, Prometheus 의 pull 은 *우체부가 정기적으로 우편함 (/metrics) 을 열어보기*.
> 주민이 사라져도 우체부가 *우편함 자체가 없어진 것* 을 즉시 안다 (up=0) — 죽은 target 자동 감지가 강력한 이유.

## 1. Pull vs Push

Prometheus 는 **pull-based**:
- Prometheus 가 정기적으로 (`scrape_interval`) target 의 `/metrics` 호출
- target 은 그저 메트릭을 노출만 — 능동적으로 push 안 함

**장점**:
- target 자체가 단순 (HTTP 핸들러 1개)
- 죽은 target 자동 감지 (`up=0`)
- target 발견을 Service Discovery 가 담당

**단점**:
- 단명 batch job 메트릭 어려움 → Pushgateway 사용
- 외부망 target 어려움 → SSH tunnel / 프록시

> **🧠 "Pull 의 *서비스 디스커버리* 가 진짜 핵심"**
> Push 라면 *주민이 우체국 주소를 알아야 한다* (앱이 메트릭 endpoint 를 알아야 함) — 환경마다 설정 변경 필요.
> Pull 은 우체부가 알아서 우편함을 찾는다 (K8s API watch) — 앱은 *그저 /metrics 만 노출* 하면 끝.

## 2. 핵심 컴포넌트

```
┌──── Prometheus Server ────────────────┐
│   ┌────────────────┐                  │
│   │ Service        │  ← K8s API watch │
│   │ Discovery      │                  │
│   └─────┬──────────┘                  │
│         ▼                             │
│   ┌────────────────┐                  │
│   │ Scraper        │ HTTP GET /metrics│
│   └─────┬──────────┘                  │
│         ▼                             │
│   ┌────────────────┐                  │
│   │ TSDB (local)   │ disk: WAL + chunks│
│   └─────┬──────────┘                  │
│         ▼                             │
│   ┌────────────────┐                  │
│   │ Query engine   │ ← PromQL         │
│   │ (PromQL)       │                  │
│   └────────────────┘                  │
│         ▼                             │
│   ┌────────────────┐                  │
│   │ Rules / Alerts │ → Alertmanager   │
│   └────────────────┘                  │
└───────────────────────────────────────┘
```

> **🧠 "한 프로세스에 *모든 단계* 가 들어있다 — 그래서 빠르다"**
> Scrape → 저장 → 쿼리 → 알람이 단일 바이너리 안에서 메모리/디스크 공유.
> 그래서 학습 / 중소 클러스터엔 Prometheus 1대로 충분 — *분산 시스템이 필요해지는 건* 메트릭 수십만 시계열 이상 단계.

## 3. TSDB (Time Series Database) 구조

### 3.1 한 개의 시계열 (time series) =

```
metric_name{label1=v1, label2=v2, ...}  →  [(t1, v1), (t2, v2), ...]
                                             ─── samples ───
```

**예**:
```
http_requests_total{method="GET", path="/api", status="200", pod="x-1"}
   →  (1700000000, 100), (1700000015, 105), (1700000030, 110), ...
```

### 3.2 라벨 조합 = 시계열 1개

같은 metric name 이라도 라벨 값이 다르면 다른 시계열:
- `http_requests_total{method="GET", status="200"}` — 시계열 A
- `http_requests_total{method="GET", status="500"}` — 시계열 B

→ **라벨이 N차원 카르테시안 곱**.

### 3.3 디스크 구조

```
data/
├── wal/                  # Write-Ahead Log (최근 ~2h)
├── 01HXXXX/              # 2h chunk
│   ├── meta.json
│   ├── chunks/000001
│   ├── index            # 라벨 → 시계열 인덱스
│   └── tombstones
├── 01HYYYY/
└── ...
```

기본 `--storage.tsdb.retention.time=15d` (학습 환경에선 1d로 줄임).

> **🧠 "2시간 chunk 가 TSDB 의 *생명*"**
> Prometheus 의 효율적 압축/쿼리는 *2h block 단위 인덱싱* 에서 온다 — 이 단위가 바뀌면 알고리즘 모두 깨진다.
> 그래서 *backup 은 block (`01HXXXX/`) 디렉토리 단위* 로 떠야지, WAL 만 떠선 데이터 복구 불가.

## 4. Cardinality — 메모리 / 디스크의 핵심 변수

**Cardinality = 시계열 수**

라벨 조합이 늘어날수록 시계열 수 폭발:
- `pod` 라벨 (Pod 100개) × `status` (5개) × `method` (4개) = 2,000 시계열 / 메트릭

```
시계열 수 ≈ 메트릭 수 × ∏(라벨 unique 값 수)
```

### 위험 패턴
- 라벨에 **user_id**, **request_id**, **timestamp** 같은 고유 값 사용 → 무한 cardinality
- 한 메트릭이 1만+ 시계열이면 점검 대상

### 측정
Prometheus UI → Status → TSDB Status:
- Top 10 label names with most series
- Top 10 series count by metric

PromQL:
```
topk(10, count by (__name__) ({__name__=~".+"}))
```

> **🧠 "Cardinality 폭발의 1위 범인은 *user_id / request_id*"**
> 라벨로 쓰면 한 사용자/요청마다 *별도 시계열* 이 생긴다 — 100만 명이면 100만 시계열.
> *고유 식별자는 메트릭이 아니라 로그* 에 속한다 — Prometheus 라벨에 절대 넣지 마라.

## 5. Service Discovery 메커니즘 (K8s)

Prometheus 는 K8s API 를 watch 해서 target 자동 발견.

옛날 방식 — `prometheus.yml` 에 `kubernetes_sd_configs`:
```yaml
- job_name: pods
  kubernetes_sd_configs:
    - role: pod
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
      action: keep
      regex: true
```

→ Pod의 `prometheus.io/scrape: "true"` annotation 으로 등록.

**Prometheus Operator 방식 (kube-prometheus-stack)**: 위를 CRD 로 추상화.

> **🧠 "Operator 방식은 *YAML 만으로* 새 target 추가 가능"**
> 옛 방식은 Prometheus 자체 config 수정 → 재시작 필요.
> ServiceMonitor 는 그저 *YAML 하나 apply* — Prometheus 가 동적 reconcile, 무중단 추가.

## 6. ServiceMonitor / PodMonitor / Probe

### 6.1 ServiceMonitor (가장 흔함)
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    release: kps     # ← Prometheus 의 selector
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
```

→ 매칭되는 Service 의 endpoints 에서 자동 scrape.

### 6.2 PodMonitor
Service 없이 Pod 직접:
```yaml
spec:
  selector:
    matchLabels: {app: worker}
  podMetricsEndpoints:
    - port: metrics
```

→ Headless Service / 외부 노출 불필요한 워크로드.

### 6.3 Probe (Blackbox)
외부 endpoint 의 health (HTTP/ICMP) 측정:
```yaml
spec:
  prober:
    url: blackbox-exporter:9115
  module: http_2xx
  targets:
    staticConfig:
      static:
        - https://api.example.com
```

> **🧠 "ServiceMonitor 가 99%, PodMonitor / Probe 는 *특수 케이스만*"**
> Service 가 없는 워크로드 (StatefulSet headless, sidecar 만) 가 PodMonitor 대상.
> 외부 endpoint 의 reachability 측정이 Probe — 둘 다 운영 환경엔 거의 안 쓰이고, ServiceMonitor 만 잘 익혀도 된다.

## 7. relabel / metric_relabel

Scrape 시 라벨 변경:
- `__meta_kubernetes_*` 를 의미있는 라벨로 변환
- 불필요한 라벨 drop

ServiceMonitor 의 `metricRelabelings`:
```yaml
metricRelabelings:
  - sourceLabels: [__name__]
    regex: 'go_gc_.*'
    action: drop          # 이 메트릭들 제외
```

→ cardinality / 디스크 절감.

> **🧠 "relabel 은 *scrape 전*, metricRelabel 은 *저장 전*"**
> 둘은 단계가 다르다 — relabel 은 *target 결정* 단계 (어떤 endpoint 를 scrape 할지), metricRelabel 은 *저장 직전* (메트릭 자체 변형).
> 잘못된 단계에 룰을 넣으면 의도와 다르게 동작 — *기본은 metricRelabel 로 drop* 가 안전한 첫걸음.

## 8. Federation

대규모 운영에서 여러 Prometheus 를 계층화:
```
[Edge Prom-1]  [Edge Prom-2]  [Edge Prom-3]   ← 각 클러스터
       ↓             ↓             ↓
       └──── /federate ────────────┘
                     ↓
            [Aggregator Prom]                  ← 중앙 집계
```

`/federate` endpoint 로 다른 Prometheus 의 메트릭을 가져옴. 단점: 자체 TSDB 라 장기 저장 한계 → 다음 모듈의 Thanos / Mimir.

> **🧠 "Federation 은 *집계용* 이지 *모든 메트릭 복제* 가 아니다"**
> 모든 raw 메트릭을 federate 하면 중앙 Prom 이 폭주.
> Recording rule 로 *집계된 메트릭 (예: NS 별 RPS)* 만 federate 하는 게 정답 — federation 은 *요약본 집계* 용도.

## 9. remote_write / remote_read

원격 저장소로 메트릭 push:
```yaml
prometheus.spec:
  remoteWrite:
    - url: https://aps-workspaces.../api/v1/remote_write
      sigv4:
        region: ap-northeast-2
```

AWS Managed Prometheus (AMP), Grafana Mimir, VictoriaMetrics 등으로 보냄.

> **🧠 "remote_write 는 *장기 저장 + 클러스터 외부* 의 표준"**
> federate (pull) 는 중앙 Prom 의 부담, remote_write (push) 는 edge Prom 의 부담.
> 대규모 환경엔 *각 클러스터의 edge Prom 이 AMP/Mimir 로 remote_write* 하는 게 확장성 측면에서 정답.

다음: [lab-01-scrape-anatomy.md](./lab-01-scrape-anatomy.md)
