# 이론 — Jaeger 아키텍처, 저장의 난제, 백엔드 선택, v2 전환, 조사 동선

> **🌱 17세 눈높이 비유: 대형 병원의 진료 기록 보관소**
> - **span** = 진료 기록 한 장 (어느 과에서 몇 시부터 몇 시까지 무엇을)
> - **trace** = 한 환자의 그날 여정 전체 (접수→내과→검사실→약국)
> - **저장의 난제** = 기록은 각 과에서 **따로따로, 다른 시간에** 도착합니다. "이 환자의 기록이 다 왔다"는 순간을 아무도 모릅니다
> - **trace_id 조회** = 환자번호로 그날 기록 전부 꺼내기 (빠르고 단순)
> - **탐색 조회** = "지난주 내과에서 30분 넘게 걸린 환자들" (역인덱스가 필요 — 비쌉니다)
> - **백엔드 선택** = 환자번호 조회만 하면 창고형(쌉니다), 온갖 조건 검색을 하려면 색인 도서관(비쌉니다)
> - **Jaeger v2** = 접수 창구(수집)를 표준 창구(OTel)로 바꾸고, 병원은 **보관·검색·열람실**에 집중

---

## 1. 아키텍처 — v1과 v2

```
[v1 — 레거시]
  앱(Jaeger SDK) → jaeger-agent(UDP) → jaeger-collector → 저장소 → jaeger-query → UI
                                            ↑ Thrift/자체 프로토콜

[v2 — 현재]
  앱(OTel SDK) → OTel Collector ────────▶ Jaeger v2 (= OTel Collector + jaeger 확장)
                    (OTLP)                    ├ 저장 익스포터 (Cassandra/ES/...)
                                              ├ query 서비스
                                              └ UI
★ Jaeger는 수집 계층을 표준(OTel Collector)에 넘기고 저장·질의·UI에 집중했습니다
   실무 함의: jaeger-agent는 폐기 경로. 신규는 OTel Collector로 보냅니다 (12의 토폴로지)
```

## 2. 트레이스 저장의 난제

```
① 쓰기 편중: 초당 수만 span, 그중 99%는 다시 읽히지 않습니다
② 분산 도착: 한 트레이스의 span들이 서로 다른 서비스·시각에 도착
             → "트레이스 완성" 시점을 알 수 없습니다 (읽을 때 조립합니다)
③ 상반된 읽기:
   - trace_id 정확 조회: 키-값 조회 (쌉니다)
   - 탐색 조회: service + operation + tags + duration 범위 + 시간 범위 (역인덱스 필요, 비쌉니다)
④ 짧은 보존: 며칠~2주 — 오래된 트레이스의 가치는 급락(대신 메트릭이 장기 추이를 맡습니다)
```

### 저장 모델

```
span 단위 저장 + 인덱스:
  spans 테이블/인덱스:  trace_id → [span, span, ...]        (조회는 trace_id로 모아 조립)
  service_index:        service+operation+시간 → trace_id들
  duration_index:       service+지연 버킷+시간 → trace_id들
  tag_index:            tag k/v+시간 → trace_id들            ★ 태그 검색의 비용 원천
```

핵심 통찰: **탐색 조회를 지원하려면 그만큼의 인덱스를 쓰기 시점에 만들어야 합니다** — 쓰기가 압도적인 시스템에서 인덱스는 곧 비용입니다. 그래서 백엔드가 갈립니다.

## 3. 백엔드 선택 — "검색을 얼마나 할 것인가"

| 백엔드 | 성격 | 탐색 검색 | 운영 | 비고 |
|---|---|---|---|---|
| **Cassandra** | 쓰기 최적 분산 KV | 제한적(인덱스 테이블) | 무겁습니다(09의 판단 프레임!) | Jaeger의 전통 |
| **Elasticsearch / OpenSearch** | 역인덱스 | **강력**(태그·전문 검색) | 무겁고 비쌈 | 태그 검색이 중요하면 |
| Badger / 메모리 | 단일 노드 | 제한적 | 가볍습니다 | 개발·소규모 |
| (Grafana **Tempo**) | 오브젝트 스토리지 + trace_id 인덱스 | **거의 없음**(TraceQL로 확장 중) | 매우 저렴 | "trace_id는 로그·메트릭에서 온다"는 철학 |

### 선택 축

```
질문: 우리는 trace_id를 어디서 얻는가요?
  A) 로그·메트릭(exemplar)에서 옵니다 → 탐색 검색이 거의 불필요 → 싼 저장(Tempo류) 유리
  B) "느린 요청 찾아줘"를 트레이스 UI에서 합니다 → 인덱스 필요 → ES/OpenSearch
★ 신호 간 상관(06·12)이 잘 되어 있을수록, 트레이스 백엔드는 싸도 됩니다
  이것이 06 지도의 "행 간 연결"이 저장 비용까지 좌우한다는 실무 함의
```

## 4. Jaeger의 분석 기능 — 저장 위에 얹은 가치

```
서비스 그래프(Service Performance Monitoring):
  span에서 서비스 간 호출·지연·에러율을 집계 → 의존 그래프 (메트릭으로 파생)
  ★ 트레이스에서 메트릭을 만드는 것 — spanmetrics connector(OTel Collector)와 같은 아이디어

트레이스 비교(Compare):
  두 트레이스의 span 트리를 diff — "느린 요청은 정상과 무엇이 다른가"

지연 히스토그램·산점도:
  같은 오퍼레이션의 지연 분포 → 롱테일 클릭 → 그 트레이스로 (SLO 조사의 입구)

Critical path 분석:
  트레이스에서 실제로 전체 시간을 지배한 경로 (cicd 23의 critical path와 같은 개념!)
```

## 5. 조사 동선 — 이 모듈의 목적지

```
1. 알람: SLO 위반 (메트릭 — 11)
2. 진입: 그 시간대·서비스의 지연 히스토그램 → 롱테일 선택
   (또는 메트릭의 exemplar가 직접 trace_id를 줍니다 → 3으로 점프)
3. 트레이스: span 트리에서 critical path의 병목 구간 식별
4. 비교: 정상 트레이스와 diff — 무엇이 추가·지연됐나
5. 로그: 그 span의 trace_id로 로그 조회 (06의 행 간 연결)
6. 원인: 코드·의존성·리소스
★ 트레이스 백엔드의 가치는 저장이 아니라 이 동선의 속도입니다
```

## 6. 운영 고려사항

```
보존: 트레이스는 짧게(7~14일). 장기 추이는 메트릭(11)이 맡습니다
샘플링: 12의 tail 샘플링으로 에러·느린 것만 → 저장량 급감, 조사 가치는 유지
       (adaptive sampling: Jaeger는 서비스별 목표 처리량에 맞춰 확률 자동 조정도 지원)
카디널리티: 태그(속성)를 인덱싱하면 검색은 좋아지고 저장·쓰기는 비싸집니다
           — 11의 카디널리티 교훈이 여기서도 (인덱싱할 태그를 화이트리스트로)
용량: span 수 × 평균 크기 × 보존일 — tail 샘플링 후 값으로 산정
HA: query는 stateless(복제 쉬움), 저장 백엔드가 실질 SPOF (09의 판단 프레임 적용)
```

## 7. 소스/도구에서 확인하기

- Jaeger: https://www.jaegertracing.io/docs — architecture, deployment, sampling
- Jaeger v2 (OTel 기반): https://www.jaegertracing.io/docs/2.0/
- spanmetrics connector: https://github.com/open-telemetry/opentelemetry-collector-contrib
- Tempo(대비군): https://grafana.com/docs/tempo/
- 06·12 복습: 격자와 Collector

## 요약 카드

| 질문 | 답 |
|------|----|
| 저장의 난제? | 쓰기 편중 + span 분산 도착(완성 시점 모름) + 상반된 읽기(정확 vs 탐색) |
| Jaeger v2? | 수집을 OTel Collector에 넘기고 저장·질의·UI에 집중 — 표준 수렴의 표본 |
| 백엔드 축? | "trace_id를 어디서 얻는가" — 로그·exemplar에서 오면 싼 저장, UI 탐색이면 인덱스 |
| ES vs Cassandra? | 태그 검색 강함(비쌈) vs 쓰기 최적(검색 제한) |
| 서비스 그래프? | 트레이스에서 메트릭 파생(spanmetrics와 같은 아이디어) |
| 조사 동선? | SLO 알람 → 지연 롱테일 → span 트리 병목 → 정상과 비교 → trace_id로 로그 |
| 운영 급소? | 보존은 짧게, tail 샘플링으로 저장량↓, 인덱싱 태그는 화이트리스트(카디널리티) |
