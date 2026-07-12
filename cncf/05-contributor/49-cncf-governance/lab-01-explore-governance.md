# Lab 01 — TOC·TAG·졸업 심사 실제 탐방

> CNCF 거버넌스의 놀라운 점은 **전부 공개**라는 것입니다. TOC의 결정·졸업 심사·TAG 회의가 모두 GitHub에 있습니다. 이 랩은 그 1차 자료를 직접 탐방해 "거버넌스가 실제로 도는 모습"을 확인합니다. 브라우저만 있으면 됩니다.

## 1. TOC 저장소 탐방 — 결정의 현장

https://github.com/cncf/toc 에 접속합니다.

```
볼 것:
  /process/       — 프로젝트 신청·승격·졸업 절차 문서
  Issues          — 실제 프로젝트들의 승격 신청과 심사 진행
  PRs             — 절차 개정 논의

과제 ①: Issues에서 "graduation" 라벨(또는 검색)로
  실제 진행 중/완료된 졸업 심사를 하나 찾아 읽어라.
  관찰 포인트:
  - Due Diligence 문서에 무엇이 검증되나
    (기여자 다양성 통계, 보안 감사 결과, 채택 사례 목록...)
  - 누가 의견을 내나 (TOC 멤버·TAG·커뮤니티)
  - 시간이 얼마나 걸리나 (수개월이 보통 — 엄격함의 증거)
```

**관찰** — 45에서 "Graduated를 신뢰"한 근거가 이 공개 심사입니다. 예컨대 어느 프로젝트의 졸업 이슈를 열면, 기여자 소속 분포 그래프·서드파티 보안 감사 링크·프로덕션 사용자 인터뷰가 붙어 있습니다. 이 검증의 무게가 성숙도 배지의 실체입니다.

## 2. 졸업 기준 원문 읽기

https://github.com/cncf/toc/blob/main/process/graduation_criteria.md

```
과제 ②: 기준 원문에서 다음을 확인하세요:
  - "committers from at least two organizations" (기여자 다양성)
  - 보안 관련 요구 (감사·취약점 프로세스·배지)
  - 거버넌스 요구 (문서화·투명성)

그리고 스스로 답하세요:
  Q. 왜 "두 조직 이상의 커미터"가 졸업 요건인가요?
  A. 한 회사 의존이면 그 회사가 떠날 때 프로젝트가 죽습니다
     (45의 NovaMetrics 사고) — 지속성의 구조적 보장
```

## 3. TAG 탐방 — 참여 장벽이 낮은 진입로

TAG 목록: https://www.cncf.io/people/technical-advisory-groups/

```
과제 ③: 자기 관심 도메인의 TAG 하나를 골라 탐방:
  TAG Security → github.com/cncf/tag-security
  TAG Observability → github.com/cncf/tag-observability
  ...

볼 것:
  - 회의 일정·줌 링크 (공개! 누구나 참석 가능)
  - 회의록 (지난 논의 열람)
  - 산출물 (백서·가이드 — 예: TAG Security의 공급망 백서는
    cicd 21에서 배운 내용의 원전)

관찰 포인트:
  TAG는 코드가 아니라 문서·리뷰·자문이 주 산출물
  → 코드 자신 없는 초보자도 기여 가능한 진입로 (50에서 활용)
```

## 4. K8s SIG 실제 보기

https://github.com/kubernetes/community/blob/master/sig-list.md

```
과제 ④: SIG 하나(예: SIG-Docs 또는 관심 영역)를 골라:
  - README에서 Chair·회의 일정 확인
  - 유튜브에서 최근 SIG 회의 녹화 하나를 10분만 보라
    (검색: "SIG-Docs meeting")

관찰 포인트:
  - 회의가 완전히 공개 (아젠다·녹화·회의록)
  - 참석자들이 여러 회사 소속 (다양성의 실제)
  - 신규 참여자 환영 절차가 있음
→ "참여해도 되나요?"의 답: 이미 문이 열려 있습니다
```

## 5. KEP 하나 읽기 — 기능은 어떻게 태어나나

https://github.com/kubernetes/enhancements/tree/master/keps

```
과제 ⑤: 배운 기능의 KEP를 찾아 읽어라.
  추천: sidecar containers(24에서 스침), Gateway API,
        server-side apply 등 — keps/sig-XXX/ 디렉터리에서

KEP 구조 관찰:
  Summary / Motivation (왜 필요한가)
  Goals / Non-Goals (★ 범위 — 27의 "좁히는 것도 설계"!)
  Proposal / Design Details
  Test Plan / Graduation Criteria (알파→베타→GA 조건)

→ 커리큘럼에서 쓴 기능들이 이 문서·논의·승인 과정을 거쳐 태어났습니다
→ 기능 제안이란 "PR 던지기"가 아니라 이 과정에 참여하는 것
```

## 6. 정리

- TOC·졸업 심사·TAG·SIG가 **전부 공개** — 거버넌스가 투명하게 실제로 돕니다
- 졸업 기준(기여자 다양성·감사·거버넌스)이 45의 신뢰 근거의 실체
- TAG는 문서·자문 중심이라 진입 장벽이 낮은 참여로 (50의 진입로)
- SIG 회의는 공개·녹화 — 문은 이미 열려 있습니다
- KEP에서 기능의 탄생 과정을 봄 — Goals/Non-Goals에 27의 설계 철학
- **★ 사용자에서 기여자로의 첫걸음 = 이 공개된 과정을 구경하는 것에서 시작**
