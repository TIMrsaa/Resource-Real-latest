# 17 — Helm v4 심화: 차트 제작과 운영

> 지금까지 Helm을 "설치 도구"로만 썼습니다(ingress-nginx 등). 이제 차트를 직접 만들고, 템플릿 함수와 의존성, 릴리스 운영까지 — **Helm v4 기준** (v3는 2026-07 지원 종료).

## 학습 목표

1. 차트 구조(Chart.yaml/values/templates/_helpers)와 렌더링 파이프라인을 압니다
2. 템플릿 문법(values 참조, 조건/반복, include, toYaml)을 다룹니다
3. 직접 만든 앱 차트로 dev/prod 환경 분리를 구현합니다
4. 릴리스 수명주기(install/upgrade/rollback/history)와 hooks를 다룹니다
5. 차트 의존성(Chart.yaml dependencies)과 lint/test를 압니다

## 선행: 모듈 04~09 (만들 차트의 재료들) · 환경: 공유 EKS
## 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-build-chart.md](./lab-01-build-chart.md) — 차트 제작 + 환경 분리
3. [lab-02-release-ops.md](./lab-02-release-ops.md) — upgrade/rollback/hooks/의존성
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h
