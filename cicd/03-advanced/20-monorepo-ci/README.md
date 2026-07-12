# 20 — 모노레포 CI: "이 커밋이 무엇에 영향을 주는가"

> 저장소가 커지면 CI의 적은 빌드 속도가 아니라 **낭비**가 됩니다 — README 오타 수정이 전체 테스트 40분을 돌린다면, 파이프라인이 아무리 빨라도 진 것입니다. 이 모듈은 모노레포 CI의 유일한 본질 질문 "이 변경이 무엇에 영향을 주는가(affected)"를 3단계(path filter → 의존성 그래프 → Bazel)로 풀고, 06의 동적 매트릭스와 03의 `ci` 게이트를 모노레포 규모로 확장합니다.

## 학습 목표

1. 모노레포의 CI 문제가 "빌드 속도"가 아니라 "영향 범위 계산"임을 설명합니다
2. path filter의 한계(의존성 무지)를 실험으로 확인하고, 그래프 기반 affected(Nx/Turborepo)로 넘어갑니다
3. "같은 입력 → 같은 출력" 캐시(로컬/원격)가 19의 콘텐츠 주소 캐시와 같은 원리임을 압니다
4. affected 목록으로 동적 매트릭스(06)를 만들어 영향받은 프로젝트만 병렬 빌드합니다
5. required check + 스킵된 잡의 함정을 알고 `ci` 게이트(03)로 해결합니다

## 선행: 02(브랜치 전략), 03(`ci` 게이트), 06(동적 매트릭스), 19(캐시 원리) · 도구: node/npm, gh
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-affected-graph.md](./lab-01-affected-graph.md) — path filter의 맹점 → 그래프 affected → 캐시
3. [lab-02-ci-integration.md](./lab-02-ci-integration.md) — 동적 매트릭스 + required check 게이트
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h
