# 44 — 테스트: 내 변경이 옳음을 증명하는 법

> K8s에서 "테스트 없는 PR"은 리뷰조차 시작되지 않습니다. 단위/통합/e2e의 3층 테스트를 직접 돌리고 작성하며, PR을 지키는 CI(prow)의 언어를 배웁니다 — 45의 마지막 준비물.

## 학습 목표

1. 테스트 3층(unit/integration/e2e)의 역할과 비용을 구분합니다
2. K8s 스타일 단위 테스트(table-driven + fake client)를 읽고 작성합니다
3. integration 테스트(실제 etcd + API 서버)를 로컬에서 돌립니다
4. e2e 프레임워크와 prow/CI의 동작(`/retest`, 테스트 그리드)을 이해합니다
5. "버그 수정 = 실패하는 테스트 먼저"의 작업 순서를 몸에 붙입니다

## 선행: 모듈 41(빌드 환경), 42(코드 지도), 31(fake client의 informer 감각) · 환경: 로컬

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-unit-tests.md](./lab-01-unit-tests.md) — 단위 테스트: 읽기, 돌리기, 작성
3. [lab-02-integration-e2e.md](./lab-02-integration-e2e.md) — 통합/e2e + prow의 언어
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h
