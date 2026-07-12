# 12 — GitLab CI: 같은 원리, 다른 문법 (그리고 통합의 철학)

> 03~08에서 GitHub Actions를, 09~11에서 AWS Code 시리즈를 배웠습니다. GitLab CI는 세 번째 세계입니다 — 그런데 여기서 배울 것은 새 도구가 아니라 **원리의 이식성**입니다. 스테이지·잡·아티팩트·러너·캐시는 이름만 다를 뿐 같은 개념이고, 진짜 차이는 GitLab의 철학("하나의 DevOps 플랫폼")에 있습니다. 이 모듈은 `.gitlab-ci.yml`을 Actions 지식으로 빠르게 읽고, 두 도구의 설계 결정이 갈리는 지점을 짚습니다.

## 학습 목표

1. `.gitlab-ci.yml`의 구조(stages·jobs·rules·needs)를 Actions 개념으로 매핑합니다
2. GitLab 러너(shared/group/specific, executor 종류)를 Actions 러너와 비교합니다
3. GitLab의 통합 철학(내장 레지스트리·환경·리뷰앱)이 주는 것과 대가를 압니다
4. DAG 파이프라인(`needs`)과 parent-child 파이프라인으로 복잡한 흐름을 구성합니다
5. "도구 이식성" — 한 CI를 이해하면 다른 CI를 빠르게 읽는 능력을 체득합니다

## 선행: 03(Actions 실행 모델), 05(테스트), 06(재사용) · 도구: GitLab 계정(무료) 또는 개념 학습
## 비용: GitLab.com 무료 티어 CI 분 내

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-gitlab-pipeline.md](./lab-01-gitlab-pipeline.md) — 파이프라인 작성, Actions와 나란히 비교
3. [lab-02-runners-and-integration.md](./lab-02-runners-and-integration.md) — 러너, 내장 기능, DAG
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
