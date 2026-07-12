# Lab 02 — 프로젝트 거버넌스 문서 읽기 훈련

> 기여할 프로젝트를 고르기 전의 **정찰 훈련**입니다. 커리큘럼에서 배운 프로젝트 두세 개의 거버넌스 문서를 실제로 읽고, 의사결정 구조·기여 절차·성장 사다리를 파악해 "기여자 관점의 프로젝트 프로필"을 작성합니다.

## 훈련 틀 — 기여자 정찰 시트

프로젝트마다 이 시트를 채웁니다:

```
프로젝트: ________
1. 의사결정: 누가 어떻게? (합의제/투표/BDFL/SIG)
2. 기여 절차: DCO/CLA? 커밋 규칙? 테스트 요구?
3. 리뷰 구조: 내 PR을 누가 승인? (OWNERS/CODEOWNERS)
4. 성장 사다리: member→…→maintainer 요건?
5. 소통 채널: 슬랙? 메일링? 회의?
6. 건강 신호: 메인테이너 다양성? 외부 PR 처리 속도?
7. 초보 진입로: good first issue? 멘토링?
```

## 예시 ① — Prometheus (11에서 배움)

https://github.com/prometheus/prometheus 를 정찰합니다.

```
실제 확인 (파일을 직접 열어보세요):
  GOVERNANCE.md (prometheus/docs 또는 루트):
    → 팀 멤버 합의제 + 투표 규정, 팀 멤버 자격·제명 절차까지 명문화
  MAINTAINERS.md:
    → 컴포넌트별 메인테이너 (여러 회사 소속 — 다양성 확인)
  CONTRIBUTING.md:
    → DCO 서명(git commit -s), PR 절차, 스타일

기여자 관점 요약:
  중간 규모 합의제 — K8s의 SIG처럼 무겁지 않고
  개인 프로젝트처럼 불투명하지도 않음
  진입: good first issue 라벨 + 컴포넌트별 메인테이너에 멘션
```

## 예시 ② — Kubernetes (SIG 체계)

```
실제 확인:
  kubernetes/community 저장소:
    governance.md — SIG 분권 구조 전체
    membership.md — ★ contributor ladder의 교과서:
      member(가입: 기여 이력+스폰서 2인)
      → reviewer(OWNERS 등재, 리뷰 이력)
      → approver(머지 승인권, 높은 신뢰)
      → subproject owner / SIG chair
  OWNERS 파일 (아무 디렉터리나):
    → reviewers/approvers 명단 — 내 PR의 승인자를 여기서 압니다

기여자 관점 요약:
  가장 체계적이되 가장 절차 많음
  진입: SIG 하나를 골라(회의 참석) → good first issue
  → "K8s에 기여"가 아니라 "SIG-X에 기여"로 접근해야 (49 theory 3절)
```

## 예시 ③ — 자기 관심 프로젝트

```
과제: 커리큘럼에서 가장 흥미로웠던 프로젝트 하나를 골라
     (Cilium? ArgoCD? Backstage? NATS?...)
     정찰 시트 7항목을 직접 채워라.

이 시트가 50(기여 실전)의 대상 선정 자료가 됩니다.
채우다 막히는 항목(예: ladder가 없습니다?)이 있으면
그것 자체가 건강 신호 판독입니다 (theory 5절).
```

## 비교 관찰 — 거버넌스의 스펙트럼

```
정찰을 마치면 보이는 것:

  K8s: SIG 분권 + 정교한 ladder (거대 프로젝트의 필연)
  Prometheus: 팀 합의제 (중간 규모의 균형)
  소규모 프로젝트: 메인테이너 몇 명의 비공식 합의

→ 정답 구조는 없습니다 — 규모에 맞는 구조가 있습니다 (48의 3층과 같은 원리)
→ 기여자에게 중요한 것: 구조가 "문서화·공개"되어 있고 실제로 돌며,
  외부인이 성장할 사다리가 있는가
```

## 경고 신호 실습 — 나쁜 거버넌스 알아보기

```
가상의 프로젝트 Z를 정찰했더니:
  - GOVERNANCE.md 없음
  - 커미터 12명 전원이 같은 회사
  - 외부 PR 평균 처리: 수개월 방치 다수
  - 결정은 사내 회의에서 (공개 기록 없음)
  - good first issue 0개

판독:
  "오픈소스"지만 실질은 한 회사의 공개 코드
  → 기여해도 성장 사다리 없음 (외부인은 영원히 외부인)
  → 채택 관점에서도 45의 지속성 리스크
  → 기여 대상으로 부적합 (코드가 아무리 멋져도)
```

## 정리

- 기여 전 정찰: GOVERNANCE·CONTRIBUTING·OWNERS·MAINTAINERS·ladder를 실제로 읽기
- K8s(SIG 분권·정교한 ladder) ↔ Prometheus(팀 합의제) — 규모에 맞는 구조
- 내 PR의 운명은 OWNERS/CODEOWNERS가 정합니다 — 승인자를 알고 시작
- 경고 신호: 문서 부재·단일 회사 커미터·외부 PR 방치·사다리 없음
- **★ 정찰 시트가 50의 기여 대상 선정 자료 — 코드 매력이 아니라 거버넌스 건강으로 고릅니다**
