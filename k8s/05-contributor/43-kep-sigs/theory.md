# 이론 — SIG 구조, KEP 프로세스, 커뮤니케이션 지도

> **🌱 17세 눈높이 비유: 거대한 학생회**
> 전교생 수만 명의 학교를 학생들이 자치로 운영한다고 합시다. 전체 회의로는 아무것도 못 정합니다 — 그래서:
> - **부서(SIG)**: 체육부, 도서부처럼 영역별 상설 조직 — 각자 자기 영역의 규칙과 예산을 결정
> - **TF(WG)**: "축제 준비위"처럼 여러 부서에 걸친 한시 조직 — 일 끝나면 해산
> - **기획서(KEP)**: "매점에 키오스크 도입" 같은 큰 변경은 반드시 서면 기획서 → 담당 부서 승인 → 시범 운영(Alpha) → 확대(Beta) → 정식(GA)
> 신입생(우리)이 할 일: 관심 부서의 **회의록을 읽고, 단톡방에 들어가는 것**부터.

---

## 1. SIG (Special Interest Group) — 상설 조직도

K8s의 모든 코드/문서/프로세스는 어느 SIG의 소유입니다 (42의 OWNERS `labels: sig/...`가 그 표식).

| 분류 | 예 | 우리가 배운 모듈과의 대응 |
|------|----|--------------------------|
| 수직(컴포넌트) | sig-node, sig-scheduling, sig-api-machinery, sig-network, sig-storage | 26, 25, 21, 27-28, 08 |
| 수평(전체 관통) | sig-architecture, sig-security, sig-scalability, sig-testing | 32-33, 37, 44 |
| 앱/운영 | sig-apps, sig-cli, sig-autoscaling, sig-cluster-lifecycle | 04, 10, 13, 35 |
| 프로젝트 운영 | sig-release, sig-docs, sig-contributor-experience | 29(릴리스), 45 |

각 SIG의 실체 (kubernetes/community 리포의 `sig-<이름>/` 디렉터리):
- **차터**(관할 범위), **리더**(Chair=운영, Tech Lead=기술 방향)
- 정기 화상 회의(공개! 녹화 공개), Slack 채널(#sig-xxx), 메일링리스트
- 산하 서브프로젝트 (예: sig-cluster-lifecycle 산하의 kubeadm, kind)

**WG(Working Group)**: SIG 횡단 한시 조직 (예: WG Batch, WG Device Management) — 목적 달성 시 해산.

## 2. KEP (Kubernetes Enhancement Proposal) — 의사결정의 단위

"사소하지 않은 모든 변경"은 KEP을 거칩니다. 위치: kubernetes/enhancements 리포의 `keps/sig-<주인>/NNNN-<이름>/`.

### KEP 문서의 뼈대 (읽는 법)

```
README.md 안의 필수 섹션:
  Summary / Motivation        왜 필요한가 — 가장 먼저 읽을 곳
  Goals / Non-Goals           범위 — "이건 다루지 않는다"가 특히 정보량 높음
  Proposal / Design Details   어떻게 — API 변경, 동작 명세
  Graduation Criteria         Alpha→Beta→GA 각 승격의 조건 ★
  Drawbacks / Alternatives    검토했지만 버린 설계 — 보석 같은 학습 자료
kep.yaml:
  stage(alpha/beta/stable), latest-milestone, feature gate 이름, 담당 SIG
```

### 기능의 일생과 KEP (모듈 29 연결)

```
KEP 승인(provisional→implementable)
 → 구현 PR들 (feature gate 뒤, 기본 off)  → Alpha 출시
 → 피드백/버그 수정, Graduation Criteria 충족 → Beta (대부분 기본 on)
 → 프로덕션 검증 → GA(stable), gate 제거 수순
어느 단계에서든: 치명적 결함 발견 시 후퇴/폐기 가능
```

→ 모듈 29의 "FEATURE STATE: v1.NN [beta]" 배지 뒤에는 반드시 이 서류와 이력이 있습니다. **"이 기능 왜 이렇게 동작해?"의 최종 답변처가 KEP입니다.**

## 3. 커뮤니케이션 지도 — 어디서 말하나

| 채널 | 용도 | 비고 |
|------|------|------|
| GitHub 이슈/PR | 공식 기록 — 결정은 결국 여기 | 검색 먼저 (중복 이슈 금물) |
| Slack (slack.k8s.io) | 실시간 질문/논의 — #sig-xxx, #kubernetes-novice | 초대 자동, 무료 |
| 메일링리스트 (groups.google.com) | dev@kubernetes.io + SIG별 | 회의 공지/중요 논의 |
| SIG 정기 회의 (Zoom) | 누구나 참관 가능, 안건은 회의 문서에 | 녹화가 YouTube에 |
| 격주 Community Meeting | 프로젝트 전체 소식 | 입문자에게 분위기 파악용 |

질문 에티켓: ① 검색 먼저(이슈/문서/Slack 히스토리) ② 맥락+시도한 것+질문을 한 번에 ③ 답엔 감사를 — 평판이 곧 신뢰 자본인 세계입니다.

## 4. 기여 전 행정 — 한 번만 하면 되는 것들

1. **CLA 서명** (필수): CNCF CLA에 서명해야 PR이 접수됩니다 — 미서명 PR은 봇이 차단. 개인이면 EasyCLA에서 몇 분
2. GitHub 계정 2FA 활성화
3. (나중에) 멤버십: 기여 이력이 쌓이면 org member 신청 — 그 전까지 PR의 CI는 멤버가 `/ok-to-test`를 해줘야 돕니다 (45에서 체험)

## 5. 거버넌스 한 장 요약

```
조타위원회(Steering Committee)  — 프로젝트 전체 거버넌스 (선출직)
   └ SIG들 — 영역별 기술 결정 (차터로 위임)
       └ 서브프로젝트 — 구체 코드베이스 (OWNERS로 위임)
원칙: 결정은 가능한 낮은 곳(SIG)에서, 공개적으로, 문서로.
```

## 6. 소스/도구에서 확인하기

- SIG 목록/차터: https://github.com/kubernetes/community/blob/master/sig-list.md
- KEP 리포: https://github.com/kubernetes/enhancements
- KEP 템플릿(섹션 정의): keps/NNNN-kep-template/
- 기여자 가이드: https://www.kubernetes.dev/docs/guide/
- CLA: https://github.com/kubernetes/community/blob/master/CLA.md

## 요약 카드

| 질문 | 답 |
|------|----|
| 코드의 주인? | OWNERS의 sig 라벨 → 그 SIG의 차터/채널 |
| 큰 변경의 절차? | KEP 승인 → gate 뒤 구현 → Alpha→Beta→GA |
| KEP에서 가장 정보 많은 섹션? | Non-Goals와 Alternatives (버린 설계) |
| 승격 조건은 어디에? | KEP의 Graduation Criteria |
| 질문은 어디서? | Slack #sig-xxx (실시간) / 이슈 (공식 기록) |
| PR 전 필수 행정? | CLA 서명 (없으면 봇이 차단) |
