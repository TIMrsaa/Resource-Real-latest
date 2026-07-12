# Lab 03 — Federation 시연

> **🌱 Federation 이 뭔가?**
> **Federation** = 한 Prometheus 가 다른 Prometheus 의 메트릭을 scrape 하는 방식.
> = "Prometheus 위의 Prometheus" 트리 구조.
>
> **언제 쓰나?**
> - 클러스터마다 로컬 Prometheus 가 있고, 중앙에서 일부만 모아 전체 뷰 만들고 싶을 때
> - 글로벌 SLO 대시보드 (cluster A + B + C 의 RPS 합)
>
> **/federate endpoint** = Prometheus 가 자기 데이터를 다른 Prometheus 에게 노출하는 특수 endpoint.
> 일반 /metrics 와 달리 PromQL `match[]` 파라미터로 필터 가능.

## 1. /federate endpoint 확인

```bash
curl -sG http://localhost:9090/federate \
  --data-urlencode 'match[]={__name__="up"}' \
  | head -10
```

기대:
```
# TYPE up untyped
up{instance="...",job="..."} 1 1700000000123
up{instance="...",job="kube-state-metrics"} 1 ...
```

→ 다른 Prometheus 가 이 endpoint 를 scrape 하면 메트릭을 그대로 받음.

> **🧠 일반 /metrics 와 /federate 의 차이**
> | 항목 | /metrics | /federate |
> |------|----------|-----------|
> | 누가 노출 | 앱 자체 | Prometheus 자기 자신 |
> | 데이터 출처 | 현재 메모리 | TSDB 의 최신 샘플 |
> | 필터 | 불가 (전부) | `match[]` PromQL selector |
> | 타임스탬프 | 보통 없음 | **있음** (원본 scrape 시점) |
> | 용도 | scrape 대상 | Prometheus 간 데이터 이동 |
>
> 타임스탬프가 있다는 게 핵심 — 중앙 Prometheus 가 "이 데이터는 5초 전에 측정됨" 을 알 수 있음.

## 2. 가상 시나리오 — 이 클러스터 외에 다른 Prometheus 가 federate 한다고 가정

다른 Prometheus 의 scrape 설정 예시:
```yaml
scrape_configs:
  - job_name: 'federate-eks-study'
    scrape_interval: 30s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~".+"}'
        - 'up'
        - '{__name__=~"http_request.+"}'
    static_configs:
      - targets:
          - 'eks-study-prom.example.com:9090'
```

`honor_labels: true` 가 핵심 — 원본 Prometheus 의 라벨 보존.

> **🧠 `honor_labels: true` 가 왜 필수인가?**
> Prometheus 는 scrape 시 자동으로 `job`, `instance` 라벨을 부여 (자기 설정 기반).
> federate 시 받은 메트릭에 이미 `job=order-svc` 가 있는데, 중앙 Prom 가 또 `job=federate-eks-study` 로 덮으면 **원본 정보 소실**.
>
> - **`honor_labels: false`** (기본): 중앙 Prom 의 라벨이 우선 → 원본 job 사라짐 → 무의미한 데이터
> - **`honor_labels: true`**: 원본 라벨 우선 → 원본 클러스터의 메트릭 라벨 그대로 보존
>
> federation 에선 항상 true. 일반 scrape 에선 false (중앙 통제).

> **🧠 `match[]` 필터의 중요성**
> federate 는 매번 모든 시계열을 HTTP 응답으로 보냄. 필터 없으면 거대 응답 → 네트워크/메모리 폭발.
> 보통 다음 중 하나만:
> - **고수준 SLI 메트릭** (`http_request_*`, `up`, recording rule 결과)
> - **cluster summary** (이미 집계된 sum/avg)
>
> raw 메트릭 (`container_cpu_usage_seconds_total` 등) 통째로 federate = 안티패턴.

## 3. Federation 의 한계

- 메트릭 양이 크면 /federate 응답이 거대 (수 MB 이상)
- 자체 TSDB 라 장기 저장 어려움
- 중복 시계열 (같은 메트릭이 두 Prometheus 에서)

→ **현대적 대안** — `remote_write`:
```yaml
prometheus.spec:
  remoteWrite:
    - url: https://remote-storage.example.com/api/v1/write
```

원격 저장소 (Thanos, Mimir, AMP) 로 메트릭 push.

> **🧠 federation vs remote_write 의 결정적 차이**
> | 항목 | federation | remote_write |
> |------|-----------|--------------|
> | 방향 | Pull (중앙이 가져감) | Push (각 Prom 가 보냄) |
> | 데이터 | 필터 후 일부 | 전부 (또는 write_relabel 로 필터) |
> | 지연 | scrape interval (~30s) | 거의 실시간 (초당 배치) |
> | 부하 | 중앙 Prom 부담 | 각 Prom 부담 (queue) |
> | 저장소 | 중앙 Prometheus | 외부 storage (S3 등) |
> | 멱등성 | 매 scrape 마다 | 한 번만 보냄 (재시도 큐) |
>
> **결론**: 새 시스템은 거의 항상 remote_write. federation 은 레거시 또는 특수 경우.

## 4. Multi-Cluster 패턴 비교

| 패턴 | 특징 |
|------|------|
| **Federation** | 각 클러스터 Prom + 중앙 Prom 가 /federate 로 가져옴 |
| **remote_write** | 각 클러스터 Prom 이 중앙 storage 로 push |
| **Single Prometheus + multi-cluster scrape** | 한 Prom 가 여러 클러스터의 endpoint 직접 scrape (네트워킹 복잡) |
| **Thanos sidecar** | 각 Prom 옆에 Thanos sidecar → S3 로 저장 → 중앙 Querier 가 통합 |

본 커리큘럼 다음 모듈 (Module 23) 에서 Thanos / AMP 도입.

> **🧠 패턴 선택 기준**
> - **클러스터 1~2개 + 가벼운 중앙 뷰** → Federation OK
> - **클러스터 3~10개 + 통합 쿼리 필요** → remote_write to AMP/Mimir
> - **장기 보관 (1년+) 필요** → Thanos sidecar + S3
> - **AWS 매니지드 선호** → AMP (인증/HA 자동)
>
> 학습 클러스터에선 Federation 으로 개념 이해 → 운영에선 remote_write/AMP.

## 5. AWS Managed Prometheus (AMP) 미리보기

remote_write 로 AMP 에 보내는 패턴:
```yaml
remoteWrite:
  - url: https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}/api/v1/remote_write
    sigv4:
      region: ${REGION}
    queueConfig:
      maxSamplesPerSend: 1000
      maxShards: 200
      capacity: 2500
```

AMP 의 장점:
- 무한 retention (15개월)
- HA 자동
- AWS IAM 으로 인증 (sigv4)

비용: ingestion + query 별 과금.

> **🧠 `queueConfig` 튜닝의 의미**
> remote_write 는 메트릭을 큐에 쌓아 배치로 보냄. 큐가 막히면 → 메트릭 손실.
>
> | 파라미터 | 의미 | 튜닝 가이드 |
> |---------|------|-----------|
> | `maxSamplesPerSend` | 한 번에 보낼 샘플 수 | 1000~5000 (큰 값 = 처리량 ↑, 지연 ↑) |
> | `maxShards` | 병렬 워커 수 | 메트릭 양에 따라 100~500 |
> | `capacity` | 워커 큐 깊이 | maxSamplesPerSend 의 2~5배 |
>
> 모니터링: `prometheus_remote_storage_samples_pending` 이 계속 늘면 큐 부족 → maxShards 증가.
>
> **sigv4** = AWS 의 서명 방식. IRSA 로 부여된 IAM Role 권한으로 자동 서명. (별도 access key 불필요)

## 학습 확인

1. /federate 와 remote_write 의 결정적 차이는?
2. honor_labels 가 false 면 무슨 일이 벌어지나?
3. Prometheus 자체 retention 을 30일로 했을 때 한계는?

> **힌트**:
> 1. Pull vs Push. federate 는 중앙이 가끔 끌어옴 (지연 + 일부), remote_write 는 각 Prom 가 거의 실시간 push (전체). 장기 저장도 remote_write 만 가능.
> 2. 중앙 Prometheus 가 자기 `job`, `instance` 라벨로 덮어씀 → 원본 클러스터 정보 소실 → 어느 클러스터에서 온 메트릭인지 모름.
> 3. 메모리 ↑ (head 가 30일치), 디스크 ↑, 노드 fail 시 30일치 손실. → 결국 외부 저장소 (S3/AMP) 필요.

다음: [quiz.md](./quiz.md)
