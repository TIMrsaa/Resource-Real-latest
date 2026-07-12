# 11 — Prometheus 심층: pull 모델, TSDB, 그리고 카디널리티라는 중력

> 06의 격자에서 [메트릭 × 수집·저장·질의] 칸을 통째로 차지한 프로젝트. CNCF 두 번째 졸업생이고, 사실상 메트릭의 표준입니다. 이 모듈은 세 가지를 팝니다: **왜 pull인가**(push와의 철학 차이가 운영 차이를 만듭니다), **TSDB는 어떻게 시계열을 저장하나**(head block → WAL → 압축된 블록, 그리고 카디널리티가 왜 메모리를 먹는가), **PromQL의 사고 모델**(레이트와 게이지, 시간 창의 함정). eks 12~13에서 CloudWatch로 배운 관측을 여기서 원리로 되짚습니다.

## 학습 목표

1. pull 모델의 구조적 이점(대상 목록 = 진실, up 메트릭, 디버깅 가능성)과 push가 필요한 예외를 압니다
2. TSDB의 저장 구조(head/WAL/블록/컴팩션)를 그리고, 카디널리티가 메모리를 잡아먹는 경로를 설명합니다
3. PromQL의 네 가지 데이터 타입과 `rate()`의 함정(counter reset·시간 창·align)을 압니다
4. 서비스 디스커버리와 relabeling — Prometheus의 진짜 확장 지점 — 을 실습합니다
5. 단일 Prometheus의 한계와 Thanos/Mimir로의 분화 지점을 판단 기준으로 압니다

## 선행: 06(관측 지도), eks 12·13(관측·SLO), k8s(메트릭 기초) · 도구: kind, kubectl, helm, promtool
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-tsdb-and-cardinality.md](./lab-01-tsdb-and-cardinality.md) — 저장 구조 관찰, 카디널리티 폭발 재현
3. [lab-02-promql-and-relabel.md](./lab-02-promql-and-relabel.md) — PromQL 함정, 서비스 디스커버리·relabeling
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
