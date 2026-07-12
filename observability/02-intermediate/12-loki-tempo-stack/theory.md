# 이론 — Loki 설계, LogQL, Tempo, 상관 배선, 판단 축

> **🌱 17세 눈높이 비유: 도서관 두 곳과 서고, 그리고 상호 대출**
> - **OpenSearch(모든 단어 색인 도서관)** = 책의 모든 단어를 카드로 만들어 어떤 단어로도 즉시 검색 — 카드 서랍이 책만큼 큼(비용)
> - **Loki(책등 라벨만 색인)** = 책등의 분류표(네임스페이스·앱·레벨)만 색인, 내용은 압축해 창고(오브젝트 스토리지)에 — 찾을 땐 분류표로 서가를 좁힌 뒤 그 칸을 훑음. 서랍이 아주 작음(저비용), 대신 "아무 단어나 전체 검색"은 느림
> - **Tempo(사건 번호 보관소)** = 사건 번호(trace_id)로만 철해 둠 — 번호는 어디서? 다른 기록(로그·통계 견본)에 적혀 있음
> - **상호 대출(상관)** = 통계표의 각주(exemplar)에 사건 번호 → 보관소에서 사건 파일 → 파일 속 시각·이름으로 도서관 로그 검색 — 세 기관이 서로를 부름
> - **핵심** = 각 저장소가 "자기가 잘하는 검색"만 맡고, 연결 고리(trace_id·라벨)로 릴레이

---

## 1. Loki의 설계 — 인덱스를 좁힌 대가와 보상

```
저장 구조:
  스트림 = 라벨 조합 {namespace="shop", app="payment", level="error"}
  스트림별로 로그를 압축 청크로 → 오브젝트 스토리지(S3 등)
  인덱스 = 라벨 → 청크 위치 (본문은 인덱스에 없음!)

검색의 동작:
  {app="payment"} |= "timeout"
  ① 라벨로 스트림·청크를 좁힘 (인덱스 — 빠름)
  ② 좁혀진 청크 안을 순차 검색 (brute force — 여기가 일)
  → 시간 범위·라벨을 좁힐수록 빠릅니다 (검색 습관이 설계에 종속)

라벨 규율 (03과 동일한 물리!):
  스트림 수 = 라벨 조합의 곱 — 스트림마다 청크·인덱스 항목
  unbounded(trace_id·user_id·pod IP)를 라벨로 → 스트림 폭발
  → ★ 라벨은 소수(namespace·app·level·cluster), 나머지는 본문 필드로
  → Fluent Bit/Collector가 붙이는 k8s 메타 중 무엇을 라벨로 승격할지가
    Loki 설정의 요체 (06의 kubernetes 필터 출력을 선별)
```

## 2. LogQL — 두 단계 문법

```
로그 쿼리 = 스트림 선택 + 파이프라인:
  {namespace="shop", app="payment"}         # 라벨 (인덱스 사용)
    |= "timeout"                            # 본문 포함 필터 (grep)
    | json                                  # ★ JSON 파싱 → 필드 추출 (02의 보상)
    | level="error"                         # 파싱된 필드로 필터
    | line_format "{{.event}} {{.user_id}}" # 출력 가공

메트릭 쿼리 (로그에서 메트릭을!):
  rate({app="payment"} |= "timeout" [5m])           # 로그 발생율
  sum by (level) (count_over_time({namespace="shop"} | json [5m]))
  → 계측 없는 레거시의 에러율도 로그로 근사 가능
  → 단, 정식 메트릭(03)의 대체가 아니라 보완 (비용·정밀도)
```

## 3. Tempo — ID 중심 저장과 TraceQL

```
저장: trace_id 키로 오브젝트 스토리지에 — 인덱스 최소
철학: "트레이스는 ID로 찾아온다" (로그·exemplar가 ID의 출처)
TraceQL: { .service.name="payment" && duration > 1s }
  — 속성 검색도 가능해졌지만(발전 중), 주력은 여전히 ID 착지
OTLP 수신: 11의 gateway exporter를 otlp/tempo로 바꾸면 끝
  (Collector 구조 덕에 백엔드 교체가 exporter 한 줄 — 11의 설계 보상)
```

## 4. 상관 배선 3종 (이 모듈의 본체)

```
① 로그 → 트레이스 (Loki 데이터소스의 derived fields):
   정규식/JSON 필드에서 trace_id 감지 → "Tempo에서 보기" 버튼 자동 생성
   전제: 로그에 trace_id 필드 (02의 규약 — 여기서 보상!)

② 트레이스 → 로그 (Tempo 데이터소스의 trace to logs):
   span의 시간 범위 ± 여유 + 라벨 매핑(k8s.namespace.name → namespace)
   으로 Loki 쿼리 생성 → "이 span의 로그" 버튼
   전제: 라벨 체계의 일관성 (06의 kubernetes 필터와 11의 k8sattributes가
   같은 대상에 같은 값을 붙여야 — 이름 매핑 설정으로 흡수)

③ 메트릭 → 트레이스 (exemplar):
   계측 SDK가 histogram 관측에 trace_id 견본 첨부
   Prometheus가 exemplar 저장(--enable-feature=exemplar-storage)
   Grafana 그래프의 점(◆) 클릭 → Tempo로
   전제: exemplar 지원 계측 + 기능 플래그

닫히는 원:
  메트릭(무엇이 이상)→①´트레이스(어디가)→②로그(왜)→라벨로 메트릭 복귀
  01의 릴레이가 클릭의 원으로 — 조사 동선의 완성형
```

## 5. 로그 저장소 3파전 예고 (13·18에서 완성)

```
              Loki              OpenSearch(18)      CloudWatch Logs(13)
인덱스        라벨만             전문 역색인          관리형(쿼리 시 스캔 과금)
비용 구조     저장 저렴          인덱스·노드 비쌈      수집(ingest)이 비쌈!
검색          라벨+grep         모든 단어 즉시        Logs Insights(스캔)
운영          자체(가벼움)       자체(무거움 — 18)     없음(관리형)
어울림        Grafana 상관       강력한 분석·보안 로그  AWS 통합·소규모

→ 판단은 18에서 정리 — 여기선 "설계가 비용 구조를 정한다"는 축만
```

## 6. 소스/도구에서 확인하기

- Loki: grafana.com/docs/loki — labels·LogQL·storage
- Tempo: grafana.com/docs/tempo — TraceQL·metrics-generator
- Grafana 데이터소스: derived fields·trace to logs·exemplar 설정
- cncf 45(Loki·Thanos 자리매김)·13(Jaeger와의 대비)

## 요약 카드

| 질문 | 답 |
|------|----|
| Loki 설계? | 라벨만 인덱스 + 본문은 압축 청크(오브젝트 스토리지) — 저비용, 좁혀서 grep |
| Loki 라벨 규율? | 메트릭과 동일(03) — 소수·유한만, trace_id는 본문 필드로! |
| LogQL? | {라벨} + 파이프라인(|= grep, | json, | 필드 필터) + rate/count 메트릭화 |
| Tempo? | trace_id 중심 오브젝트 스토리지 저장 — ID는 로그·exemplar에서 옵니다 |
| 배선 3종? | derived fields(로그→트레이스)·trace to logs(→로그)·exemplar(메트릭→) |
| 배선의 전제? | trace_id 로그 필드(02)·라벨 일관성(06↔11)·exemplar 계측 |
| 로그로 메트릭? | rate({...}|="x"[5m]) — 레거시 보완용 (정식 메트릭 대체 아님) |
| 3파전 축? | 인덱스 설계=비용 구조 — Loki(라벨)/OpenSearch(전문)/CW(관리형·ingest 과금) |
