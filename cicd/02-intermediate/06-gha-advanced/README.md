# 06 — GitHub Actions 심층: 중복을 없애고 배포를 통제합니다

> 03에서 워크플로 하나를 만들었습니다. 저장소가 열 개가 되면 그 YAML이 열 벌 복사되고, 액션 버전을 올리는 날 열 번 고쳐야 합니다. 이 모듈은 **재사용의 문법**(reusable workflow / composite action / 조직 스타터)과 **배포의 통제**(environments, 승인, 배포 브랜치 제한)를 다룹니다. 그리고 재사용이 만드는 새 위험 — 중앙 워크플로가 곧 중앙 폭발 반경 — 도 함께.

## 학습 목표

1. 재사용 3수단(reusable workflow / composite action / 스타터 워크플로)을 **선택 기준으로** 구분합니다
2. `workflow_call`의 인터페이스(inputs·secrets·outputs)를 설계합니다 — 시크릿 전달의 두 방식
3. environments로 배포 게이트를 만듭니다: 승인자, 대기 시간, 배포 브랜치 제한, 환경 시크릿
4. 매트릭스를 동적으로 생성합니다 (`fromJSON`) — 모노레포의 affected 빌드 준비(20)
5. 재사용의 위험을 압니다 — 버전 고정, `inherit` 시크릿의 폭발 반경

## 선행: 03(실행 모델·격리 경계), 04(빌드), 05(테스트 배치) · 도구: gh CLI, GitHub 조직(개인 계정도 가능)
## 비용: 퍼블릭 저장소 무료

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-reusable.md](./lab-01-reusable.md) — reusable workflow와 composite action을 각각 구현·비교
3. [lab-02-environments.md](./lab-02-environments.md) — 승인 게이트, 환경 시크릿, 동적 매트릭스
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
