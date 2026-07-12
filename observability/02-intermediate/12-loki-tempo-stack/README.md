# 12 — Loki·Tempo와 신호 상관: 점프가 되는 순간

> intermediate 트랙의 마무리이자 수확의 순간. 지금까지 만든 파이프라인들(로그 06~07, 메트릭 08~10, 트레이스 11)에 **저장 백엔드**를 달고 — Loki(라벨 기반 로그, "로그의 Prometheus식 접근")와 Tempo(오브젝트 스토리지 기반 트레이스) — 이 모듈의 진짜 목표인 **신호 상관(correlation)**을 완성합니다: Grafana에서 메트릭 그래프의 이상 지점(exemplar) 클릭 → 해당 trace → 그 span의 로그(trace_id 필터) → 다시 메트릭. 01부터 예고한 "조사 동선의 릴레이"가 클릭으로 이어지는 순간입니다. Loki의 설계 철학(전문 인덱스 없이 라벨만 — 비용을 좁힌 설계)과 LogQL, trace_id 로그 규약(02)의 보상도 여기서 확인합니다.

## 학습 목표

1. Loki의 설계(라벨 인덱스만·청크 저장)와 LogQL 기본을 익힙니다 — 라벨 규율은 메트릭과 동일
2. Tempo에 트레이스를 저장하고 TraceQL로 찾습니다
3. Grafana 데이터소스 연결(derived fields·exemplar)로 신호 간 점프를 구성합니다
4. "메트릭→트레이스→로그" 조사 동선을 클릭으로 완주합니다
5. Loki vs OpenSearch(18) vs CloudWatch Logs(13)의 판단 축을 미리 세웁니다

## 선행: 06(Fluent Bit), 08(Prometheus), 09(Grafana), 11(OTel) — 전부 이 모듈에서 합류 · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-loki-tempo-setup.md](./lab-01-loki-tempo-setup.md) — Loki·Tempo 배포, 파이프라인 연결
3. [lab-02-correlation.md](./lab-02-correlation.md) — 상관 구성과 동선 완주 (트랙 캡스톤)
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
