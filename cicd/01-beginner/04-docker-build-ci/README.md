# 04 — CI에서 이미지 빌드: 캐시, 레이어, 그리고 불변 태그

> 01에서 "한 번 빌드, 여러 번 배포"(아티팩트 불변성)를 원칙으로 세웠습니다. 이 모듈은 그 아티팩트 — 컨테이너 이미지 — 를 **빠르고, 작고, 재현 가능하게** 만드는 법입니다. 러너는 매번 새 VM이므로(03) 캐시는 저절로 남지 않습니다. 레이어가 어떻게 캐시되는지 알면 3분 빌드가 30초가 되고, 모르면 캐시를 넣어도 매번 미스가 납니다.

## 학습 목표

1. 이미지 레이어와 캐시 무효화 규칙을 압니다 — **한 줄의 순서**가 빌드 시간을 좌우합니다
2. 멀티스테이지 빌드로 빌드 도구와 런타임을 분리합니다 (크기 + 공격 표면)
3. GitHub Actions에서 BuildKit 캐시(GHA cache / registry cache)를 연결합니다
4. 태그 전략을 세웁니다 — `:latest`가 왜 아티팩트 불변성을 파괴하는가
5. ECR에 푸시하고 **다이제스트로 배포**하는 파이프라인 조각을 만듭니다

## 선행: 01(아티팩트 불변성), 03(Actions 실행 모델·캐시), Docker 기본기 · 도구: Docker, gh, AWS CLI
## 비용: ECR 저장 소량(무료 티어 500MB) — cleanup에서 삭제

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-layers-and-cache.md](./lab-01-layers-and-cache.md) — 캐시 무효화를 로컬에서 실측
3. [lab-02-ci-build-push.md](./lab-02-ci-build-push.md) — Actions에서 빌드·캐시·ECR 푸시
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
