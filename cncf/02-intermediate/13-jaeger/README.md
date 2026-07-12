# 13 — Jaeger 심층: 트레이스를 저장하고 되찾는 법

> 12에서 트레이스를 **만들고 보냈다면**, 이 모듈은 그것이 **어디에 어떻게 앉고, 어떻게 검색되는가**입니다. 06의 격자에서 [트레이스 × 저장·질의·UI] 칸의 주인. 핵심 난제는 하나입니다 — 트레이스는 쓰기가 압도적으로 많고(초당 수만 span) 읽기는 드문데, 읽을 때는 "trace_id로 정확히" 또는 "서비스·태그·지연으로 탐색"이라는 상반된 접근을 요구합니다. 이 모듈은 그 난제를 저장 모델(span 인덱스 vs 트레이스 조립)과 백엔드 선택(Cassandra/ES/OpenSearch), 그리고 Jaeger v2가 OTel Collector 위로 재건축된 사건까지 팝니다.

## 학습 목표

1. Jaeger의 아키텍처(collector/query/UI + 저장 백엔드)와 v1→v2 전환(OTel Collector 기반)을 압니다
2. 트레이스 저장의 난제 — 쓰기 편중, span 분산 도착, 인덱스 설계 — 를 이해합니다
3. 백엔드 선택(Cassandra vs Elasticsearch/OpenSearch vs Tempo류)의 축을 압니다
4. 트레이스 검색·분석 기능(서비스 그래프, 비교, 지연 히스토그램)을 실습으로 활용합니다
5. 12의 샘플링·전파 지식과 결합해 "트레이스로 장애를 좁히는" 동선을 완성합니다

## 선행: 06(격자), 12(OTel — 필수) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-storage-and-search.md](./lab-01-storage-and-search.md) — 저장 백엔드, 인덱스, 검색의 실제
3. [lab-02-trace-driven-debugging.md](./lab-02-trace-driven-debugging.md) — 트레이스로 장애 좁히기(서비스 그래프·비교)
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
