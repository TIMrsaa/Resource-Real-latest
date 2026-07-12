# 26 — 관측 OSS 기여 실전: 빌드에서 첫 PR까지

> Part 5의 마지막 모듈. 25에서 고른 대상의 코드를 **실제로 빌드**하고(fluent-bit·Prometheus·OTel Collector — 세 갈래의 빌드·개발 루프를 모두 익힙니다), 자기 빌드를 이 파트의 실습 환경(kind)에서 돌려 보고, 이 파트의 경험에서 나온 **첫 기여**(문서·재현 이슈·작은 수정·플러그인/컴포넌트)를 cncf 50의 규율(작게·DCO·예절)대로 제출합니다. 커리큘럼 전체의 결론과 같습니다 — 졸업장은 자격증이 아니라 기여 이력입니다. 관측을 배운 사람의 기여는 특별한 이점이 있습니다: **자기 기여의 효과를 자기가 만든 관측으로 검증할 수 있습니다.**

## 학습 목표

1. 세 갈래 빌드를 수행합니다: fluent-bit(C/CMake), Prometheus·exporter(Go), OTel Collector(builder)
2. 자기 빌드를 kind 환경에서 실행·검증합니다 (수정→빌드→배포→관측의 개발 루프)
3. Collector 커스텀 빌드(builder)로 컴포넌트 조합을 만듭니다 — contrib 기여의 기반
4. 이 파트의 마찰에서 나온 첫 기여를 규율(50)대로 제출합니다
5. 지속 계획(25의 ADR + 50 lab-02의 로드맵)을 확정합니다 — Part 5 수료

## 선행: 25(대상 선정 — 필수), cncf 50(기여의 길), 해당 언어 기초 · 도구: git, Go, C 툴체인(선택), kind
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-build-three-ways.md](./lab-01-build-three-ways.md) — 세 갈래 빌드와 개발 루프
3. [lab-02-first-contribution.md](./lab-02-first-contribution.md) — 첫 기여 제출 (파트의 졸업 과제)
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 3h (그리고 기여는 여기서부터 계속)
