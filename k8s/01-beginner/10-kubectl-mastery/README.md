# 10 — kubectl 완전정복

> 초급 졸업 모듈. 지금까지 산발적으로 쓴 kubectl을 체계화하고, 디버깅/자동화에 쓰는 고급 기능(explain, jsonpath, diff, patch, debug)을 장착합니다.

## 학습 목표

1. `explain`으로 문서 없이 모든 필드를 탐색합니다
2. jsonpath/custom-columns/sort-by로 원하는 데이터를 추출합니다
3. apply vs create vs patch vs edit의 차이와 diff 워크플로를 압니다
4. `kubectl debug`(ephemeral container)로 셸 없는 컨테이너를 디버깅합니다
5. 명령형 제너레이터(`--dry-run=client -o yaml`)로 YAML 뼈대를 빠르게 만듭니다

## 선행: 모듈 01~09 전부 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-explore-extract.md](./lab-01-explore-extract.md) — explain/jsonpath/columns 훈련
3. [lab-02-mutate-debug.md](./lab-02-mutate-debug.md) — diff/patch/debug 훈련
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md)

소요: 이론 30m + 실습 1.5h
**초급 수료 체크**: 이 모듈의 퀴즈를 포함해 모듈 01~10 퀴즈를 다시 풀어 80% 이상이면 중급(02-intermediate)으로.
