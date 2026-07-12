# 자가 점검 퀴즈

**Q1.** argo-cd 3컴포넌트의 역할과, 14에서 배운 "refresh vs sync"가 각각 어느 코드에 사는지 말하세요.

**Q2.** gitops-engine이 별도 저장소인 역사적 배경과, 경계 판정 규칙·2단계 여정을 설명하세요.

**Q3.** `make start-local`이 보여주는 컨트롤러의 본질(k8s 42 연결)과, 그것이 디버깅에 주는 이점은?

**Q4.** 버그 수정 PR의 올바른 순서와, "빨강→초록 diff"가 왜 가장 설득력 있는 PR 본문인가요?

**Q5.** 26(actions/runner)과 27(argoproj)의 거버넌스 차이가 기여 전략을 어떻게 바꾸나요?

**Q6.** 신규 기여자의 문 순서(docs → UI → 경계 명확 영역 → 코어)의 근거는?

**Q7.** proposal이 필요한 변경의 기준과, 건너뛰었을 때의 리스크는?

**Q8.** Rollouts(17)에서 첫 코드 기여로 인기 있는 영역과 그 이유는?

---

## 정답

**A1.** application-controller: 기대(Git) vs 실제(클러스터) 비교와 sync 결정 — reconcile 루프(appcontroller.go, 비교는 state.go의 CompareAppState). repo-server: Git·Helm·Kustomize를 매니페스트로 렌더링(+캐시). server: API(gRPC/REST)·RBAC·UI 서빙. refresh(비교만)는 appcontroller의 refresh 큐 처리, sync(적용)는 sync.go가 gitops-engine의 sync 패키지를 호출하는 경로.

**A2.** 배경: Argo와 Flux의 엔진 통합 시도(GitOps Engine 협력)에서 diff·sync·health 로직이 라이브러리로 추출됨 — 통합은 무산됐지만 분리 구조는 남았습니다. 판정: diff 계산·정규화·health 판정·sync wave 실행 → gitops-engine, Application CRD·컨트롤러 결정 로직·repo-server·RBAC·UI·AppSet → argo-cd. 확인법은 증상 재현 후 코드 경로가 어느 모듈로 들어가는지 추적. 2단계 여정: engine에 PR 머지 → argo-cd의 go.mod 의존 갱신 PR — 릴리스 시점 계획에 반영해야.

**A3.** 컨트롤러는 kubeconfig로 클러스터에 붙는 평범한 Go 프로세스입니다(Pod일 필요 없음) — start-local은 컴포넌트들을 로컬 프로세스로 띄워 kind를 상대로 돌립니다. 이점: IDE 디버거로 reconcile 경로에 중단점, printf 추가 후 즉시 재시작, 재컴파일→확인 루프가 초 단위 — 이미지 빌드·배포 없이 개발 루프가 돕니다(eks 28의 디버그 루프와 동형).

**A4.** ① 실패하는 재현 테스트 작성(fake client — 버그가 테스트로 고정됨) ② 수정(경계 판정 포함) ③ 그 테스트 초록 + 기존 테스트 전체 회귀 없음 ④ PR(이슈 연결, 재현→원인→수정→테스트 서술). 빨강→초록 diff는 리뷰어가 "버그가 실재했고, 이 수정이 그것을 고치며, 회귀를 막는 감시가 남는다"를 재현 노동 없이 확인하게 합니다 — 리뷰 비용 최소화가 머지 속도의 최대 변수입니다.

**A5.** 26은 기업(GitHub) 주도 — 로드맵 밖 기능 PR은 표류하기 쉬워, 재현·진단 이슈가 주 기여 형태. 27은 CNCF 오픈 거버넌스 — 머지의 길이 문서화(proposal, good first issue, 공개 미팅)되어 코드 PR이 실제로 환영받고, 절차를 통과하면 특정 회사 허락이 불필요. 전략: 26에서는 이슈 품질에, 27에서는 절차 준수(테스트·proposal)에 투자합니다.

**A6.** 리스크와 신뢰의 경사 때문. docs는 리뷰 비용이 낮고 사용자 경험(14의 상처)이 그대로 재료가 됩니다. UI는 경쟁이 덜하고 실패 반경이 작습니다. trafficrouting 같은 영역은 인터페이스 경계가 명확해 코어를 몰라도 안전하게 기여 가능. 코어(reconcile 본체)는 성능·호환성이 예민해 신규 계정의 PR이 표류하기 쉬움 — 작은 머지 실적(신뢰)이 쌓인 뒤가 효율적입니다.

**A7.** 기준: 동작 변경, CRD 필드 추가, 새 컴포넌트, 성능 특성을 바꾸는 것 — docs/proposals/의 기존 문서 크기가 감각 기준. 건너뛰면: 수 주의 구현이 "방향이 다릅니다, proposal부터"로 통째 무산될 수 있습니다 — 오픈 거버넌스는 절차를 지키면 길을 열고 건너뛰면 노동을 증발시킵니다. 가장 싼 사전 검증은 기여자 미팅에서 아이디어를 먼저 말하는 것.

**A8.** rollout/trafficrouting/의 트래픽 제공자(istio, alb, nginx...) 추가·수정 — 이유: 제공자별 인터페이스 경계가 명확해 코어 rollout 로직을 건드리지 않고, 17(카나리 스텝)·eks 14(ALB)의 사용 지식이 그대로 도메인 지식이 되며, 각 제공자가 상대적으로 독립적이라 리뷰 범위가 좁습니다. analysis/(17의 AnalysisTemplate) 쪽 메트릭 제공자 추가도 같은 성질.
