# 05 — CI의 테스트: 게이트를 신뢰할 수 있게 만드는 법

> 01에서 "신뢰의 게이트"가 Continuous Deployment의 전제라고 했습니다. 그 신뢰를 만드는 것이 테스트입니다 — 그런데 대부분의 팀은 테스트를 **가지고** 있으면서 **믿지는** 않습니다: 빨간불이 뜨면 재실행하고, 커버리지 숫자를 올리려 의미 없는 테스트를 쓰고, e2e가 20분이라 PR마다 건너뜁니다. 이 모듈은 테스트를 자산으로 만드는 구조 — 피라미드, 격리, flaky 관리, 그리고 커버리지의 올바른 사용법 — 를 다룹니다. 초급 트랙 졸업 모듈.

## 학습 목표

1. 테스트 피라미드와 그 역전(아이스크림 콘)의 비용 구조를 압니다
2. 테스트 더블(fake/stub/mock)을 구분하고, k8s 파트에서 본 fake client가 왜 그 사상인지 잇습니다
3. 통합 테스트를 CI에서 격리합니다 — service container / testcontainers
4. **flaky 테스트를 격리(quarantine)하는 시스템**을 만듭니다 — 재실행이 아니라
5. 커버리지의 올바른 용법(추세와 diff 커버리지)과 오용(목표 숫자)을 압니다

## 선행: 01(게이트 신뢰), 03(Actions 매트릭스·잡) · 도구: gh, Docker
## 비용: 없음 (퍼블릭 저장소 러너 무료)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-pyramid-and-doubles.md](./lab-01-pyramid-and-doubles.md) — 피라미드 각 층을 CI로, service container 격리
3. [lab-02-flaky-quarantine.md](./lab-02-flaky-quarantine.md) — flaky 재현·탐지·격리 시스템
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
