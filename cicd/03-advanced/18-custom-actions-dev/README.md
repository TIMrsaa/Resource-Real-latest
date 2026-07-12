# 18 — 커스텀 액션 개발: 도구를 소비자에서 생산자로

> 03~08에서 GitHub Actions를 **소비**했습니다(uses: 로 남의 액션을 씀). 이 모듈은 **생산**합니다 — 재사용 가능한 액션을 직접 만들고, 테스트하고, 마켓플레이스에 배포합니다. 그리고 그 과정에서 27(actions/runner 기여)의 기초가 되는 액션 내부 구조를 이해합니다. 06의 재사용이 "우리 조직 안"이었다면, 이 모듈은 "생태계에 기여"다.

## 학습 목표

1. 액션 세 종류(JavaScript/Docker/composite)의 구조와 선택 기준을 압니다
2. JavaScript 액션을 만듭니다 — 입력/출력, 툴킷(@actions/core), 번들링
3. 액션을 테스트합니다 — 05의 테스트 원리를 액션에 적용
4. 액션을 버전 관리하고 마켓플레이스에 배포합니다 (SHA 고정 관점 — 03)
5. 공급망 관점에서 좋은 액션의 조건(권한 최소화, 투명성)을 압니다

## 선행: 03(액션 실행 모델·인젝션), 05(테스트), 06(재사용) · 도구: Node.js, gh
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-build-action.md](./lab-01-build-action.md) — JS 액션 개발, 입출력, 테스트
3. [lab-02-publish-and-security.md](./lab-02-publish-and-security.md) — 배포, 버전 관리, 공급망 안전
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h
