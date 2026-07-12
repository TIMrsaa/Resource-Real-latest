# 학습 가이드 — 신호들이 서로를 부르게 하세요

## 이 모듈의 위치 — 수확

```
06~07: 로그가 흐릅니다 (하지만 목적지가 stdout 흉내였습니다)
08~10: 메트릭이 쌓이고 울립니다
11: 트레이스가 태어나 gateway까지 왔습니다 (백엔드가 debug였습니다)
12(지금): 진짜 저장소(Loki·Tempo)를 달고 — 셋을 잇습니다
```

잇는다는 것의 실체는 **클릭 한 번의 점프**입니다:

```
[메트릭] p99 그래프의 튀는 점 (exemplar)
   ↓ 클릭
[트레이스] 그 순간의 실제 trace — payment span이 4.8s
   ↓ "이 span의 로그" 클릭
[로그] 그 trace_id의 payment 로그 — "PG timeout, retry 3"
   ↓ 라벨 클릭
[메트릭] payment의 에러율 추세로 복귀
```

각 화살표가 이 모듈에서 구성하는 배선입니다. 배선의 재료는 이미 다 만들었습니다 — trace_id 로그 필드(02의 규약), exemplar(histogram+trace), 라벨의 일관성(k8s 메타데이터 — 06과 11의 k8sattributes가 같은 라벨을 붙이는 이유).

## Loki — "로그의 Prometheus식 접근"이 뜻하는 것

```
OpenSearch(18)의 방식: 로그 전문을 역색인 — 모든 단어로 검색 가능
  강력하지만: 인덱스가 원본만큼 큽니다 (비용·쓰기 부하)

Loki의 방식: ★ 라벨만 인덱스, 본문은 압축 청크로 오브젝트 스토리지에
  검색 = 라벨로 청크를 좁힌 뒤 → 그 안을 grep (brute force)
  → 인덱스 비용이 극적으로 작습니다 (cncf 45에서 스친 "비용을 좁힌 설계")
  → 대가: "라벨 없이 전문 검색"은 느립니다 — 시간·라벨로 좁히는 습관 전제

따라서 Loki의 라벨 규율 = 메트릭의 라벨 규율 (03!):
  라벨은 유한하게 (namespace·app·level 정도)
  ★ trace_id를 라벨로 하면 안 됨 (unbounded — 카디널리티 폭발이 Loki에도!)
    → trace_id는 본문(JSON 필드)에 두고 필터로 찾습니다
```

이 설계 감각이 "Loki가 맞나, OpenSearch가 맞나"(18) 판단의 뿌리입니다.

## Tempo — 트레이스 저장의 미니멀리즘

```
Jaeger(cncf 13)가 다양한 백엔드(Cassandra·ES)를 두는 반면,
Tempo: 오브젝트 스토리지에 trace_id로 저장 — 검색은 최소(TraceQL)
  철학: "트레이스는 ID로 찾는다" — ID는 어디서? 로그·exemplar·메트릭에서!
  → 상관이 전제된 설계 (Grafana 생태계의 일원)
  → 저장이 싸서 tail 샘플링 부담도 완화
```

## 배선의 세 가지 재료

```
① derived fields (Loki 데이터소스 설정):
   로그의 trace_id 필드를 감지 → Tempo 링크 자동 생성 (로그→트레이스)
② trace to logs (Tempo 데이터소스 설정):
   span의 시간·라벨로 Loki 쿼리 생성 (트레이스→로그)
③ exemplar (Prometheus):
   histogram 관측에 trace_id 견본을 첨부 → 그래프 점에서 트레이스로
   (메트릭→트레이스)
```

**전제 조건을 다시** — 이 배선이 작동하려면: 로그에 trace_id 필드(02·04), 라벨 체계의 일관성(로그의 namespace/app ↔ 트레이스의 k8s.namespace.name — 06·11), exemplar를 켠 계측. 상관은 우연이 아니라 설계의 산물(04의 결론)이라는 것을 배선하며 체감합니다.

## 트랙의 마무리

lab-02가 intermediate 트랙의 캡스톤입니다 — 장애 시나리오 하나를 "메트릭 알림→트레이스→로그→원인"으로 클릭 완주하고, SIGNALS-MAP의 수집·보존 칸을 전부 채웁니다. 다음 트랙(13~)에서는 같은 그림을 AWS 관리형으로 다시 그립니다 — 구조는 같고 부품이 바뀝니다.
