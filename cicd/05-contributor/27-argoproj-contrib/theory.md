# 이론 — argoproj 지도, argo-cd 3컴포넌트 해부, gitops-engine 경계, 오픈 거버넌스

> **🌱 17세 눈높이 비유: 로봇 청소기 회사에 입사하기**
> - 14에서 나는 로봇 청소기의 **사용자**였습니다 — "지도대로 청소해줘(Git이 진실), 어질러지면 다시(selfHeal)"
> - 이제 그 회사의 신입 개발자입니다. 회사는 부서가 나뉘어 있습니다:
>   - **application-controller** = 순찰·판단 두뇌 — "지도와 현실이 다른가?"를 계속 비교(reconcile)
>   - **repo-server** = 지도 제작부 — 설계도(Git·Helm·Kustomize)를 실제 지도(매니페스트)로 변환
>   - **server + UI** = 고객 상담 창구 — 사람과 CLI가 회사와 대화하는 곳
>   - **gitops-engine** = 핵심 모터 부품 — 자회사로 분리되어 다른 회사(다른 GitOps 도구)에도 납품 가능
> - **오픈 거버넌스** = 이 회사의 이사회가 여러 회사 출신 — 한 회사 마음대로가 아니라 공개 절차(proposal)로 결정
> - 신입의 첫 임무: "고장 신고가 오면 어느 부서 소관인지" 판정하는 법 배우기

---

## 1. argoproj 지도 — 4형제와 부품 저장소

| 저장소 | 무엇 | 이 커리큘럼의 접점 |
|---|---|---|
| **argo-cd** | GitOps CD 컨트롤러 | 14 — 이 모듈의 중심 |
| **argo-rollouts** | Progressive Delivery (카나리·블루그린) | 17 — AnalysisTemplate·트래픽 전환 |
| argo-workflows | K8s 네이티브 워크플로 엔진 (DAG 잡) | 16의 Tekton과 같은 자리 경쟁 |
| argo-events | 이벤트 기반 트리거 | 15의 이미지 자동화류 이벤트 연결 |
| **gitops-engine** | diff·sync 핵심 라이브러리 | argo-cd의 심장 부품 (별도 저장소!) |

CNCF Graduated(2022) — 성숙도 최고 단계로, 멀티 벤더 유지보수자와 공개 거버넌스가 심사 조건이었습니다. cncf 파트에서 이 심사 체계 자체를 다룹니다.

## 2. argo-cd 해부 — 3컴포넌트와 코드 지도

```
Git ──▶ repo-server ──매니페스트──▶ application-controller ──apply/diff──▶ 클러스터
              ▲                            │  (14의 reconcile 루프가 사는 곳)
              │                            ▼
           server (API) ◀─────────── Redis (캐시)
              ▲
        UI(React) / CLI(argocd)
```

```
argoproj/argo-cd
├── cmd/                        각 컴포넌트의 main (argocd-server, -repo-server, -application-controller)
├── controller/                 ★ application controller
│   ├── appcontroller.go            reconcile 루프의 본체 — refresh 큐, 비교, sync 결정
│   ├── state.go                    기대 상태 vs 실제 상태 비교 (14의 diff가 계산되는 곳)
│   ├── sync.go                     sync 실행 — gitops-engine 호출부
│   └── cache/                      클러스터 상태 캐시 (watch 기반 — 대규모 성능의 핵심)
├── reposerver/                 ★ Git → 매니페스트 렌더링 (Helm/Kustomize 실행, 캐시)
├── server/                     ★ API 서버 (gRPC/REST) — RBAC·프로젝트 경계(14)
├── applicationset/             ApplicationSet 컨트롤러 (14의 멀티클러스터 生成器)
├── ui/                         React + TypeScript — 열려 있는 또 하나의 문
├── docs/                       mkdocs — proposals/ 에 설계 제안들
├── test/e2e/                   e2e 테스트 (kind 기반)
└── go.mod                      → github.com/argoproj/gitops-engine 의존 확인!
```

### 14의 지식이 코드가 되는 지점

| 14에서 배운 것 | 소스의 실체 |
|---|---|
| refresh(비교) vs sync(적용)의 구분 | appcontroller.go의 refresh 큐 처리 vs sync.go의 오퍼레이션 |
| 3분 주기 + 웹훅 | appcontroller의 타이머와 refresh 트리거 경로 |
| diff의 정규화(무시 필드) | gitops-engine의 diff 패키지 + argo-cd의 normalizer |
| sync wave/hook | gitops-engine의 sync 패키지가 wave 정렬 실행 |
| OutOfSync 루프(필드 다툼) | state.go의 비교 결과가 계속 diff를 내는 것 — 25 카드 7 |

## 3. gitops-engine — 경계 판정 연습

역사: Argo와 Flux가 엔진 통합을 시도하며 sync·diff·health 로직을 라이브러리로 추출했습니다(통합은 무산됐지만 분리는 남았습니다). 판정 규칙:

```
diff 계산이 이상하다 / 정규화 / health 판정 / sync wave 순서  → gitops-engine 쪽 가능성
Application CRD·컨트롤러 동작 / repo-server / RBAC / UI / AppSet → argo-cd 쪽
확인법: argo-cd에서 재현 → 스택·코드 경로가 gitops-engine 패키지로 들어가는지 추적
        (eks 28의 코어/프로바이더 판정과 동형 — "스택 트레이스가 국경 검문소")
```

수정이 gitops-engine에 들어가면: engine에 PR → 머지 후 argo-cd의 go.mod 갱신 PR — 2단계 여정까지 계획에 넣어야 합니다.

## 4. 로컬 개발 루프 — 실클러스터를 상대로

```
make start-local                 컴포넌트들을 로컬 프로세스로 (goreman) — kind를 상대로 실행
                                 코드 수정 → 재시작 → 즉시 확인 (eks 28의 디버그 루프와 동형)
make test                        단위 테스트 (패키지 지정: go test ./controller/...)
make start-e2e && make test-e2e  e2e — kind에 실제 sync 시나리오
ui/: yarn start                  UI 개발 서버 (로컬 API 서버에 연결)
```

핵심 감각: **컨트롤러는 그냥 Go 프로세스입니다** — 클러스터 밖에서 kubeconfig로 붙어 돕니다(k8s 42에서 배운 컨트롤러의 본질). 그래서 IDE 디버거로 reconcile에 중단점을 걸 수 있습니다.

## 5. 테스트 문화 — 어디에 무엇을 쓰나

```
단위: 표준 go test + fake client — controller/state_test.go 등 (비교 로직은 순수 함수에 가깝게)
e2e:  test/e2e — 실제 kind에 Application 만들고 sync 결과 검증 (느림 — 좁게 지정해 실행)
규율: 버그 수정 PR = 그 버그를 재현하는 테스트 먼저 (k8s 44의 문법 그대로)
      "테스트 없는 수정은 리뷰에서 첫 코멘트가 테스트 요청" — 시간 아끼려면 처음부터
```

## 6. 오픈 거버넌스의 기여 문법

```
이슈: good first issue / help wanted 라벨 운영 — 26과 달리 코드 PR이 실제 환영받음
제안: 큰 변경은 docs/proposals/ 에 proposal 문서 PR → 논의 → 승인 후 구현
      (k8s의 KEP, eks 28의 RFC와 동형 — "설계 합의가 코드보다 먼저")
미팅: 공개 기여자/유지보수자 미팅 — 신규 기여자 질문 환영 (캘린더는 저장소 README)
릴리스: 분기 마이너 릴리스 주기 — 내 PR이 어느 릴리스에 실릴지 마일스톤으로 추적
문의 문 순서: 문서 오타·예제(즉시) → UI 이슈(TS) → 컨트롤러 버그(재현 테스트 동반) → proposal
```

### 26·27·28 거버넌스 비교 (이 트랙의 뼈대)

| | 26 actions/runner | 27 argoproj | 28 tektoncd |
|---|---|---|---|
| 주인 | GitHub(기업) | CNCF (멀티 벤더) | CDF (멀티 벤더) |
| 로드맵 | 회사가 결정 | 공개 proposal | 공개 TEP |
| 코드 PR | 보수적 | 환영 (절차 통과 시) | 환영 (k8s식 OWNERS) |
| 최적 기여 | 재현·진단 이슈 | 코드·UI·docs 전방위 | 코드·catalog·TEP |

## 7. 소스/도구에서 확인하기

- 기여 가이드: https://argo-cd.readthedocs.io/en/stable/developer-guide/ (로컬 실행·테스트·코드 스타일)
- gitops-engine: https://github.com/argoproj/gitops-engine — `pkg/sync`, `pkg/diff`, `pkg/health`
- proposals: https://github.com/argoproj/argo-cd/tree/master/docs/proposals
- Rollouts 기여: https://github.com/argoproj/argo-rollouts/blob/master/docs/CONTRIBUTING.md

## 요약 카드

| 질문 | 답 |
|------|----|
| argo-cd 3컴포넌트? | application-controller(reconcile) / repo-server(Git→매니페스트) / server(API·UI) |
| 14의 reconcile은 어디? | controller/appcontroller.go (비교는 state.go, 적용은 sync.go→gitops-engine) |
| 2저장소 경계? | diff·sync·health 엔진 = gitops-engine — 수정 시 engine PR → argo-cd 의존 갱신 2단계 |
| 로컬 루프? | make start-local (goreman, kind 상대) — 컨트롤러는 그냥 Go 프로세스(디버거 가능) |
| 거버넌스? | CNCF Graduated 오픈 거버넌스 — proposal·공개 미팅·멀티 벤더 (26과 대비) |
| 문 순서? | docs → UI(TS) → 컨트롤러(테스트 동반) → proposal — 자기 언어의 문부터 |
