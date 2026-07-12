# 25 — 관측 OSS 생태계: 기여 지점의 지도

> contributor 트랙의 시작. 이 파트에서 쓴 도구들 — Fluent Bit/Fluentd, Prometheus, OpenTelemetry, Grafana 스택(Loki·Tempo·Pyroscope), Thanos — 은 전부 오픈소스이고, 각자의 커뮤니티·거버넌스·기여 경로가 있습니다. 이 모듈은 cncf 49(CNCF 거버넌스)의 지식을 관측 생태계에 적용합니다: 각 프로젝트의 거버넌스 구조(fluent 패밀리·Prometheus 팀·OTel의 SIG 체계 — 관측 OSS 중 가장 큰 조직), 기여 지점의 유형(코드만이 아닙니다 — 이 파트에서 배운 것 자체가 기여 재료: 문서의 공백, 재현 가능한 버그, 계측 라이브러리, 익스포터/플러그인), 그리고 26(기여 실전)을 위한 대상 선정 — 자기 관심·역량·프로젝트 건강의 교집합 찾기입니다.

## 학습 목표

1. 관측 OSS들의 거버넌스 구조(fluent·prometheus·open-telemetry·grafana)를 파악합니다
2. OTel의 SIG 체계(스펙·언어별 SIG·Collector)와 기여 동선을 압니다
3. 기여 지점의 유형(코드·문서·플러그인·계측·트리아지)을 관측 도메인에 매핑합니다
4. cncf 49의 정찰 시트로 관측 프로젝트들을 평가합니다
5. 26을 위한 자기 기여 대상을 선정합니다 (관심×역량×건강)

## 선행: cncf 49(거버넌스 — 필수)·50(기여의 길), 이 파트 전체(도메인 지식) · 도구: 브라우저·GitHub
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-governance-tour.md](./lab-01-governance-tour.md) — 4대 생태계 거버넌스 실제 탐방
3. [lab-02-target-selection.md](./lab-02-target-selection.md) — 정찰 시트·대상 선정
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
