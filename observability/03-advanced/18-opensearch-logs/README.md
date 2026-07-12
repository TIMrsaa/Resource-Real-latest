# 18 — OpenSearch: 전문 검색 로그와 저장소 3파전의 결론

> 로그 저장소의 마지막 선택지. Loki(12)가 "라벨만 인덱스"로 비용을 좁혔다면, OpenSearch는 반대편 — **모든 필드를 역색인**해 어떤 조건으로도 즉시 검색·집계·시각화합니다(보안 로그·감사·전문 분석의 영역). 이 모듈은 역색인의 원리(왜 강력하고 왜 비싼가), 인덱스 설계(샤드·매핑·시간 기반 인덱스), ISM(수명 관리 — hot/warm/cold/delete), Fluent Bit→OpenSearch 연결(06·07의 파이프라인이 세 번째 목적지를 만남), 그리고 이 파트가 쌓아온 **로그 저장소 3파전(Loki vs OpenSearch vs CloudWatch Logs)의 최종 판단**을 다룹니다. AWS에서는 관리형(Amazon OpenSearch Service/Serverless)을 기준으로 합니다.

## 학습 목표

1. 역색인의 원리와 비용 구조(인덱스 크기·쓰기 부하)를 Loki와 대비해 이해합니다
2. 인덱스 설계(시간 기반·샤드·매핑)와 흔한 함정(샤드 과다·매핑 폭발)을 압니다
3. ISM으로 hot→warm→cold→delete 수명 계층을 설계합니다
4. Fluent Bit output을 OpenSearch로 연결하고 대량 색인의 운영 포인트를 압니다
5. 로그 저장소 3파전의 최종 판단표를 완성합니다 (사용 패턴→저장소)

## 선행: 12(Loki — 대비축), 13(CW Logs), 06·07(파이프라인) · 도구: AWS 계정(OpenSearch Service) 또는 로컬 컨테이너(개념)
## 비용: ⚠️ 발생 — OpenSearch 도메인은 시간당 과금(실습 후 즉시 삭제!). 로컬 대안 제공

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-index-and-pipeline.md](./lab-01-index-and-pipeline.md) — 인덱스 설계·파이프라인 연결·검색
3. [lab-02-ism-and-three-way.md](./lab-02-ism-and-three-way.md) — ISM 수명 관리·3파전 판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
