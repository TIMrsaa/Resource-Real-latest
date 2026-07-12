# 이론 — CNCF 구조, 프로젝트 수명주기, SIG 체계, 거버넌스 문서, 건강 판단

> **🌱 17세 눈높이 비유: 큰 학교의 학생회와 동아리 연합**
> - **재단(CNCF)** = 동아리 연합회 — 동아리(프로젝트)들이 공정하게 크도록 지원
> - **GB(이사회)** = 학교 재단 이사회 — 예산·시설 (돈)
> - **TOC(기술위)** = 선출된 학생 대표단 — 어느 동아리를 정식 인가할지, 잘 크는지 (기술)
> - **돈과 기술의 분리** = 기부 많이 한 학부모가 동아리 인가를 좌우 못 하게 (벤더 중립)
> - **TAG** = 분야별 자문단 (예술 분과, 체육 분과 — 보안·관측 등)
> - **동아리 등급** = 신생(Sandbox) → 정식(Incubating) → 명문(Graduated, 엄격 심사)
> - **SIG** = 큰 동아리(K8s)의 부서들 — 밴드부 안의 보컬팀·악기팀·공연기획팀
> - **GOVERNANCE.md** = 동아리 회칙 — 부장 뽑는 법, 결정하는 법 (없으면 사조직)

---

## 1. CNCF 구조 — 견제와 균형

```
Linux Foundation
└── CNCF
    ├── Governing Board (GB)
    │     기업 회원(멤버십 등급별)로 구성
    │     역할: 예산·마케팅·전략 (돈)
    │     ★ 기술 방향에는 관여 못 함
    │
    ├── TOC (Technical Oversight Committee)
    │     11인, 선출제 (GB·End User·프로젝트 메인테이너 등이 선출)
    │     역할: 프로젝트 승인·성숙도 심사·기술 비전 (기술)
    │     ★ 프로젝트의 입학과 졸업을 결정
    │
    ├── TAG (Technical Advisory Groups) — TOC의 눈과 손
    │     TAG Security / Observability / App Delivery /
    │     Storage / Network / Runtime / Contributor Strategy /
    │     Environmental Sustainability ...
    │     역할: 도메인 전문 자문, 프로젝트 리뷰 보조, 백서·가이드
    │     ★ 참여 장벽 낮음 — 회의 공개, 누구나 (50의 진입로!)
    │
    └── End User Community
          사용 기업들 — 피드백·요구·TOC 선출 참여

★ 핵심 설계: 돈(GB) ↔ 기술(TOC) 분리
  많이 낸 회사가 자사 프로젝트를 밀어 넣지 못하게
  → 벤더 중립 = CNCF의 존재 이유 (01)
```

## 2. 프로젝트 수명주기 — 입학부터 졸업까지

```
① Sandbox (입학)
   신청 → TOC 검토·투표
   기준: 클라우드 네이티브 정합, 오픈 거버넌스 의지, TOC 스폰서
   의미: "실험·혁신의 공간" — 성숙 보장 아님 (45!)
   혜택: 중립 재단에 IP 이전, CNCF 인프라·홍보

② Incubating (성장 증명)
   기준: 실 프로덕션 사용자 존재, 건강한 기여자 유입,
        명확한 버저닝·보안 프로세스
   심사: TOC + TAG 실사(Due Diligence)

③ Graduated (졸업 — 엄격)
   기준:
     - 기여자 다양성 (여러 조직의 커미터 — 한 회사 의존 X)
     - 거버넌스 문서·투명한 의사결정
     - 보안 감사(third-party) 통과·취약점 프로세스
     - 실 채택(다수 프로덕션)·성장 지표
     - CII/OpenSSF Best Practices 배지
   심사: TOC 실사 → 투표
   의미: "성숙·지속 가능" — 45에서 신뢰한 근거가 이 관문

④ Archived (은퇴)
   유지 안 되면 보관 처리 — 45의 "지속성 관찰"이 이래서 필요
```

## 3. Kubernetes SIG 체계 — 대형 프로젝트의 분권

```
K8s는 거대 → SIG(Special Interest Group)로 분권:

주요 SIG (일부):
  SIG-Node        kubelet·컨테이너 런타임 (26·27 영역)
  SIG-Network     Service·Ingress·CNI (04 영역)
  SIG-Storage     PV·CSI (05 영역)
  SIG-Scheduling  스케줄러 (08·44 영역)
  SIG-Auth        인증·인가 (07 영역)
  SIG-API-Machinery  API 서버·CRD (08 영역)
  SIG-Docs        문서 (★ 기여 진입로로 유명)
  SIG-Release     릴리스 관리
  SIG-Contributor-Experience  기여자 경험 (온보딩!)

각 SIG:
  자기 영역 코드·리뷰·설계 소유
  공개 회의(줌·유튜브 녹화)·슬랙 채널·메일링 리스트
  Chair(운영)·Tech Lead(기술) 리더십

WG(Working Group): SIG 가로지르는 한시 주제 (예: WG-Batch)

기능 제안 절차:
  아이디어 → SIG 논의 → KEP(Kubernetes Enhancement Proposal) 작성
  → SIG 승인 → 구현 → 알파/베타/GA (08에서 본 기능 단계!)
  ★ "PR부터 던지기"가 아니라 "SIG 논의부터" — 이걸 모르면 PR이 표류

다른 프로젝트도 유사 구조:
  Prometheus(11)·Envoy(23) 등은 더 단순(메인테이너 합의제)
  → 프로젝트마다 GOVERNANCE.md 확인 (lab-02)
```

## 4. 거버넌스 문서 — 기여 전 정찰 목록

```
GOVERNANCE.md
  의사결정 구조: 합의제? 투표? 메인테이너 전권?
  리더십 선출·교체 방법

OWNERS (K8s 계열) / CODEOWNERS (GitHub 표준)
  디렉터리별 reviewers(리뷰 권한)·approvers(머지 승인)
  → 내 PR을 누가 승인하는지 여기서 압니다

CONTRIBUTING.md
  기여 절차: DCO/CLA 서명, 커밋 규칙, 테스트 요구, PR 템플릿

MAINTAINERS.md / 커미터 명단
  현재 메인테이너 + ★ 되는 길(contributor ladder)
  예: member → reviewer → approver → maintainer
  각 단계의 요건(기여 이력·추천)

CODE_OF_CONDUCT.md
  행동 규범 (CNCF 공통 CoC 채택이 일반적)

★ 이 문서들의 존재·품질 = 프로젝트 건강 지표 (45 심화)
  없거나 형식적 → 의사결정 불투명·한 회사 의존 가능성
```

## 5. 거버넌스로 프로젝트 건강 읽기 (45 심화)

```
건강 체크리스트 (기여·채택 전):
  □ GOVERNANCE.md가 실질적인가 (의사결정이 문서대로 도나)
  □ 메인테이너가 여러 조직 소속인가 (github에서 확인 가능)
  □ 회의·설계 논의가 공개되나 (회의록·이슈·제안 문서)
  □ contributor ladder가 있나 (새 기여자가 성장할 길)
  □ 최근 릴리스·커밋이 활발한가
  □ CoC와 그 집행 체계가 있나

경고 신호:
  한 회사가 커미터 전부 / 결정이 비공개 채널에서 /
  외부 PR이 장기 방치 / ladder 없음(성장 불가)
  → 45의 "NovaMetrics 사고"를 거버넌스 렌즈로 예방
```

## 6. 벤더 중립의 실제 — 왜 기업들이 프로젝트를 기증하나

```
기업이 자사 프로젝트를 CNCF에 기증하는 이유:
  신뢰: "한 회사 것"이면 경쟁사가 채택 꺼림 → 중립 재단이면 안심
  생태계: 커뮤니티·기여자·채택의 확대
  예: Google→Kubernetes, Lyft→Envoy, Spotify→Backstage,
      AWS(→분리)→Karpenter의 core 중립화(44)

대가: 통제권 상실 (거버넌스가 커뮤니티로)
  → 이 트레이드가 생태계 전체를 키웠습니다 (K8s의 성공 공식, 02)

★ 기여자에게 의미: 중립 거버넌스 덕분에
  소속과 무관하게 실력·기여로 성장 가능 (contributor ladder)
```

## 7. 소스/도구에서 확인하기

- CNCF 거버넌스: https://github.com/cncf/toc (TOC 문서·심사 기록 전부 공개!)
- 졸업 기준: https://github.com/cncf/toc/blob/main/process/graduation_criteria.md
- K8s SIG 목록: https://github.com/kubernetes/community/blob/master/sig-list.md
- KEP: https://github.com/kubernetes/enhancements
- TAG 목록: https://www.cncf.io/people/technical-advisory-groups/

## 요약 카드

| 질문 | 답 |
|------|----|
| CNCF 핵심 설계? | 돈(GB) ↔ 기술(TOC) 분리 → 벤더 중립 |
| TOC? | 선출 11인 — 프로젝트 승인·졸업 심사·기술 비전 |
| TAG? | 도메인 자문(Security·Observability…) — 참여 장벽 낮음(진입로) |
| 수명주기? | Sandbox(실험)→Incubating(성장 증명)→Graduated(엄격 심사)→Archived |
| 졸업 기준? | 기여자 다양성·거버넌스·보안 감사·채택·배지 |
| SIG? | K8s의 분권 — 영역별 코드·리뷰·설계 소유, 제안은 KEP로 |
| 정찰 문서? | GOVERNANCE·OWNERS·CONTRIBUTING·MAINTAINERS(ladder)·CoC |
| 건강 판단? | 문서 실질성·메인테이너 다양성·공개 논의·ladder (45 심화) |
