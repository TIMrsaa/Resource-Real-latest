# 06 — 지도: 관측 — 세 신호와 대통일 운동

> eks 12~13에서 CloudWatch로 관측을 배웠다면, 이 지도는 그 오픈소스 원본 동네입니다. 구조는 세 신호(메트릭·로그·트레이스)로 잡히고, 역사는 하나의 운동으로 요약됩니다: 신호마다 따로 자라던 도구들(Prometheus·Fluentd·Jaeger)이 **수집의 표준을 OpenTelemetry로 통일**해가는 중입니다 — CNCF에서 K8s 다음으로 큰 프로젝트가 된 이유. 지도의 함정도 뚜렷합니다: 가장 많이 쓰는 화면(Grafana)과 로그 저장소(Loki)가 CNCF 밖이라는 것, 그리고 "장기 저장"이 별도 카테고리라는 것(Thanos·Mimir).

## 학습 목표

1. 세 신호의 역할 분담(무엇이 이상한가/왜/어디서)과 각 신호의 대표 스택을 그립니다
2. OpenTelemetry의 위치 — "수집·전송의 표준화"이지 저장·질의가 아님 — 를 정확히 압니다
3. Prometheus 생태(exporter·TSDB·장기 저장의 Thanos/Mimir 분화)를 지도로 그립니다
4. 로그 파이프라인(Fluentd vs Fluent Bit)과 저장(Loki — 비CNCF)의 경계를 압니다
5. kind에서 메트릭 수집(Prometheus)과 OTel Collector 파이프라인을 시식합니다

## 선행: 01(범례), k8s 중급(메트릭 기초), eks 12·13(관측·SLO), cicd 23(파이프라인 관측) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 지도 본체
2. [lab-01-category-census.md](./lab-01-category-census.md) — 전수 목록·신호별 분류
3. [lab-02-signals-taste.md](./lab-02-signals-taste.md) — Prometheus 수집 + OTel Collector 파이프라인
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
