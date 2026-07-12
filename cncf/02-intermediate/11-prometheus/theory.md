# 이론 — pull의 철학, TSDB 해부, 카디널리티의 물리학, PromQL의 사고 모델

> **🌱 17세 눈높이 비유: 학교 출석 체크**
> - **push 방식** = 학생이 등교하면 스스로 명부에 서명 — 서명이 없으면 결석인지 전학 갔는지 모릅니다
> - **pull 방식(Prometheus)** = 선생님이 **명부를 들고** 한 명씩 호명 — 대답 없으면 결석(up==0)이 즉시 확정. 명부(서비스 디스커버리)가 곧 "있어야 할 사람"의 진실
> - **시계열** = 학생 한 명의 출석 기록부 한 장. `이름 + 반 + 번호` 조합이 다르면 다른 장
> - **카디널리티 폭발** = 명부에 "학생 이름 + **오늘 입은 옷**"을 키로 잡는 것 — 매일 새 기록부가 수백 장 생기고 교무실(메모리)이 터집니다
> - **TSDB** = 기록부 보관 방식 — 오늘 것은 책상 위(head, 메모리), 하루치가 차면 묶어서 서고로(블록), 서고에서는 여러 날치를 합쳐 압축(컴팩션)
> - **WAL** = 책상 위 기록을 잃지 않으려고 옆에 대충 갈겨쓰는 노트 — 정전(크래시) 후 복구용
> - **rate()** = "요즘 지각이 늘었나요?"를 답할 때, 학기 초부터의 누적 지각 수(카운터)가 아니라 **최근 창의 기울기**를 봅니다. 그런데 학생이 전학 왔다 오면(카운터 리셋) 계산을 보정해야 합니다

---

## 1. pull 모델 — 구조가 만드는 운영 성질

| 성질 | pull(Prometheus) | push(CloudWatch·StatsD) |
|---|---|---|
| "있어야 할 대상" | **서비스 디스커버리 목록 = 진실** | 서버는 온 것만 압니다 |
| 죽음 감지 | `up == 0` (공짜) | 별도 하트비트 필요 |
| 디버깅 | 브라우저로 `/metrics` 열면 끝 | 에이전트 로그를 봐야 |
| 결합도 | 앱은 Prometheus를 모름(그냥 노출) | 앱이 목적지를 알아야 |
| 방화벽 | Prometheus → 대상 방향 필요 | 대상 → 서버 (아웃바운드만) |
| 단명 잡 | **곤란**(스크레이프 전에 죽음) | 자연스러움 |

**Pushgateway는 예외이지 대안이 아닙니다** — 단명 배치 잡(cron)이 끝나기 전에 값을 밀어넣는 용도. 서비스에 쓰면 up 감지가 사라지고, 값이 영원히 남는 안티패턴이 됩니다.

```
스크레이프 사이클:
  SD(kubernetes_sd 등)가 대상 목록 갱신 → relabel_configs로 필터·가공
  → HTTP GET /metrics (타임아웃·간격) → 파싱 → metric_relabel_configs
  → TSDB에 append (+ up{job=...} 메트릭 자동 생성)
```

## 2. TSDB 해부 — 메트릭은 어디에 어떻게 앉나

```
                    ┌──────────── 메모리 ────────────┐
스크레이프 ──▶ head block (최근 ~2~3시간)            │
              ├ 각 시계열의 인덱스(라벨 → 시계열 ID)  │
              └ 각 시계열의 열린 청크(압축 중)        │
                    │                                │
              WAL (디스크, append-only) ← 크래시 복구 │
                    └────────────────────────────────┘
  2시간마다 head → 영구 블록으로 flush
      block/ (chunks + index + meta.json + tombstones)
  컴팩션: 작은 블록들을 병합 (2h → 8h → 2일...) — 인덱스 재작성
  보존(retention) 지나면 블록 삭제
```

핵심 구조 두 가지:

- **청크(chunk)**: 하나의 시계열의 시간 구간(기본 120 샘플)을 델타·XOR로 압축 — **샘플당 평균 1~2바이트**. 그래서 "포인트가 많은 것"은 쌉니다
- **인덱스**: 라벨 → 시계열 ID의 역인덱스(포스팅 리스트). 시계열이 늘면 인덱스와 head의 메모리 구조가 선형 이상으로 커집니다 → **시계열 수가 비싼 것**

## 3. 카디널리티의 물리학 — 왜 라벨이 위험한가

```
시계열 수 = Σ (메트릭마다) 라벨 조합의 곱
  http_requests_total{method(5) × path(20) × code(6)}          = 600 시계열   ✅
  http_requests_total{... × user_id(1,000,000)}                = 6억 시계열   💀

메모리 대략치: 시계열당 수 KB(인덱스+head 청크+심볼) → 100만 시계열 ≈ 수 GB
그리고 죽는 방식이 잔인합니다:
  1) 스크레이프마다 새 시계열이 생김 → head 증가 → OOM
  2) 재시작하면 WAL 재생에 수십 분 → 그동안 관측 없음
  3) 인덱스 커짐 → 질의도 느려짐 (특히 정규식 매칭)
```

**교회 문(church door) 규칙**: 라벨 값의 집합은 **유한하고, 낮고, 시간에 따라 늘지 않아야** 합니다.

```
안전:  method, status_code, endpoint(라우트 패턴!), instance, namespace
위험:  user_id, request_id, session, 전체 URL(쿼리스트링 포함), 이메일, IP
경계:  pod_name (재배포마다 늘어남 — churn! 짧은 보존이면 감내)
```

`user_id`가 필요하면 그것은 메트릭의 질문이 아니라 **로그·트레이스의 질문**입니다(06의 신호 분업).

### 카디널리티 진단 도구

```promql
topk(10, count by (__name__)({__name__=~".+"}))      # 어느 메트릭이 시계열을 먹나
count by (job)({__name__=~".+"})                      # 어느 job이 범인인가
prometheus_tsdb_head_series                           # 현재 head 시계열 수
scrape_samples_scraped                                # 대상별 샘플 수
```
```bash
promtool tsdb analyze /prometheus                      # 오프라인 분석 — 최고 카디널리티 라벨
```

## 4. PromQL의 사고 모델

### 네 가지 타입

```
Instant vector  특정 시점의 시계열 집합       up
Range vector    시간 창을 가진 샘플들          up[5m]
Scalar          단일 숫자                     3.14
String          (거의 안 씀)
★ 함수의 입출력 타입이 안 맞으면 파싱 에러 — rate()는 range vector를 먹고 instant를 뱉습니다
```

### 카운터와 rate()의 진실

```promql
rate(http_requests_total[5m])
```

내부 동작: ① 창 안의 샘플들에서 **카운터 리셋(값 감소)을 감지해 보정** ② 첫·마지막 샘플로 기울기 ③ 창 경계까지 외삽(extrapolation). 함정 셋:

```
① 창이 스크레이프 간격의 4배 미만이면 샘플 부족 → 값이 튀거나 없음
   (15s 스크레이프면 rate 창은 1m 이상 권장)
② increase()는 rate × 창 — 외삽 때문에 소수점이 나옵니다 ("2.0003 요청")
③ irate()는 마지막 두 샘플만 — 그래프엔 예쁘고 알람엔 쓰지 마세요(스파이크에 요동)
```

### 게이지 vs 카운터 vs 히스토그램

```
counter  단조 증가(리셋 가능) → rate/increase 로만 의미 있음. 절대값 보지 말 것
gauge    오르내림 → avg/max/min, delta()
histogram 버킷 누적 카운터 → histogram_quantile(0.99, sum by(le)(rate(bucket[5m])))
  ★ 분위수는 버킷 경계의 선형 보간 — 버킷이 나쁘면 p99도 나쁩니다
  ★ 여러 인스턴스의 분위수는 평균낼 수 없습니다 (반드시 le로 합산 후 계산)
summary  클라이언트에서 분위수 계산 → 집계 불가 (히스토그램을 선호하세요)
```

## 5. 서비스 디스커버리와 relabeling — 진짜 확장 지점

```yaml
scrape_configs:
  - job_name: k8s-pods
    kubernetes_sd_configs: [{ role: pod }]
    relabel_configs:                 # ★ 스크레이프 '전': 대상 선별·주소 가공
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+)
        replacement: $1
    metric_relabel_configs:          # ★ 스크레이프 '후': 메트릭 버리기(카디널리티 방어!)
      - source_labels: [__name__]
        action: drop
        regex: "go_gc_.*"
```

- `relabel_configs`: 대상(target) 단계 — 무엇을 긁을지
- `metric_relabel_configs`: 샘플 단계 — 무엇을 저장할지 (**카디널리티 폭발의 마지막 방어선**)
- `__meta_*` 라벨: SD가 제공하는 메타데이터 (쓰고 나면 사라짐)

Operator 패턴: prometheus-operator의 `ServiceMonitor`/`PodMonitor` CRD가 이 설정을 대신 생성합니다(08의 오퍼레이터 관통 개념).

## 6. 단일 Prometheus의 한계 — 언제 분화하나

```
축 1: 보존 기간 — 로컬 디스크에 몇 달치? → 오브젝트 스토리지 필요 → Thanos sidecar / Mimir
축 2: 전역 뷰 — 클러스터 N개, 샤드 M개의 통합 질의 → Thanos Query / Mimir
축 3: 고가용성 — Prometheus 2대 실행(중복 스크레이프) → 질의 시 중복 제거 필요 → Thanos
축 4: 규모 — 단일 인스턴스 수백만 시계열 이상 → 샤딩(hashmod relabel) + 전역 질의

★ 그 전에: 카디널리티를 먼저 줄여라. 대부분의 "Prometheus가 부족하다"는
   사실 "우리가 라벨을 잘못 붙였다"입니다 (§3)
```

## 7. 소스/도구에서 확인하기

- Prometheus 문서: https://prometheus.io/docs — querying/basics, storage
- TSDB 형식: https://github.com/prometheus/prometheus/blob/main/tsdb/docs/format/README.md
- promtool: `promtool tsdb analyze`, `promtool check rules`
- prometheus-operator: https://prometheus-operator.dev
- 06 지도 복습: Thanos/Mimir의 자리

## 요약 카드

| 질문 | 답 |
|------|----|
| 왜 pull? | 대상 목록 = 진실, up 감지 공짜, /metrics로 디버깅, 낮은 결합도 |
| Pushgateway? | 단명 배치 잡의 예외 — 서비스에 쓰면 up 감지 상실(안티패턴) |
| 무엇이 비싼가? | 샘플 수가 아니라 **시계열 수**(라벨 조합) — 청크는 샘플당 1~2바이트 |
| 카디널리티 규칙? | 라벨 값은 유한·저카디널리티·시간에 안 늘어남. user_id는 로그·트레이스로 |
| rate()의 함정? | 창 ≥ 4×스크레이프 간격, increase는 외삽으로 소수점, irate는 알람 금지 |
| 히스토그램? | le 버킷 합산 후 histogram_quantile — 분위수는 평균낼 수 없습니다 |
| 마지막 방어선? | metric_relabel_configs의 drop (저장 전에 버립니다) |
| 언제 Thanos? | 보존·전역 뷰·HA·샤딩 — 단 카디널리티 정리가 먼저 |
