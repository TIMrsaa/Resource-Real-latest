# 02 — Git 워크플로: 브랜치 전략은 배포 전략입니다

> 01에서 "브랜치 수명이 CI의 성공 지표"임을 봤습니다. 그런데 대부분의 조직은 브랜치 전략을 **취향**으로 고릅니다("우린 git-flow 씁니다"). 실제로 브랜치 전략은 배포 빈도·릴리스 모델·팀 규모가 결정하는 **종속 변수**입니다. 이 모듈은 그 인과를 바로 세우고, 트렁크 기반 개발이 왜 DORA 엘리트의 공통점인지 코드로 확인합니다.

## 학습 목표

1. git-flow / GitHub flow / 트렁크 기반의 구조와 각각이 **전제하는 릴리스 모델**을 압니다
2. "브랜치 전략 → 배포 빈도"가 아니라 그 반대의 인과임을 이해합니다
3. 짧은 브랜치를 가능하게 하는 세 도구(피처 플래그·브랜치 바이 앱스트랙션·PR 크기 규율)를 익힙니다
4. 브랜치 보호 규칙과 머지 방식(merge/squash/rebase)의 실제 차이를 실험으로 확인합니다
5. 리뷰 문화의 병목을 측정합니다 — 코드 리뷰가 리드 타임의 어디를 먹는가

## 선행: 01(DORA·통합 주기), git 중급(rebase, cherry-pick) · 도구: git, gh CLI
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-branching-models.md](./lab-01-branching-models.md) — 세 모델을 같은 시나리오로 실행
3. [lab-02-protection-and-review.md](./lab-02-protection-and-review.md) — 브랜치 보호, 머지 방식, 리뷰 지표
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
