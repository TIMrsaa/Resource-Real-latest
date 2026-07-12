# 이론 — tektoncd 지도, pipeline 컨트롤러 해부, k8s식 프로세스, TEP, catalog

> **🌱 17세 눈높이 비유: 자치 규약이 잘 잡힌 동아리 연합**
> - tektoncd는 여러 동아리(저장소)의 연합입니다 — 본체 동아리(pipeline), 초인종 동아리(triggers), 소식지(cli/dashboard), 레시피 공유 게시판(catalog)
> - 연합의 규약은 옆 학교(Kubernetes)에서 검증된 것을 그대로 가져왔습니다:
>   - **OWNERS 파일** = 부서별 승인 도장 명단 — 이 폴더의 변경은 이 명단의 승인이 필요
>   - **Prow 봇** = 행정 조교 — "/lgtm"(검토 완료), "/approve"(승인) 댓글을 읽고 머지를 처리
>   - **TEP** = 기획서 게시판 — 큰 변경은 기획서로 합의부터, 코드는 그다음
> - **ko 빌드(19)** = 레시피 없이 재료에서 바로 완성품 — 고치고 `ko apply` 한 번이면 새 버전이 동아리방에
> - **catalog** = 레시피 게시판 — 코드를 몰라도 좋은 레시피(Task YAML)로 기여 가능한 가장 낮은 문

---

## 1. tektoncd 저장소 지도 — 문과 난이도

| 저장소 | 무엇 | 언어 | 문의 높이 |
|---|---|---|---|
| **pipeline** | Task/Pipeline·컨트롤러 본체 (16의 그것) | Go | 높음 — 본진 |
| triggers | EventListener·웹훅 트리거 (16 lab-02) | Go | 중간 |
| cli | tkn CLI | Go | 중간 — CLI UX 이슈 많음 |
| dashboard | 웹 UI | TS/React | 중간 — 27의 UI 문과 동형 |
| **catalog / catalog(Artifact Hub)** | 재사용 Task/Pipeline 모음 | YAML/셸 | **가장 낮음 — 추천 첫 문** |
| operator | 설치·수명주기 관리 | Go | 중간 |
| **community** | 거버넌스·TEP·행사 | 문서 | TEP 읽기가 곧 설계 학습 |

거버넌스: **CDF**(Continuous Delivery Foundation — Jenkins·Spinnaker도 여기) 소속. CNCF(27)와 재단은 다르지만 오픈 거버넌스라는 본질은 같고, 프로세스는 k8s에서 이식했습니다.

## 2. pipeline 컨트롤러 해부 — 16의 지식이 코드가 되는 곳

```
tektoncd/pipeline
├── cmd/                        controller, webhook 등 main
├── pkg/apis/pipeline/v1/       ★ CRD 타입 정의 (Task, TaskRun, Pipeline, PipelineRun)
├── pkg/reconciler/
│   ├── taskrun/                ★ TaskRun → Pod 변환·상태 추적 (16의 핵심 경로)
│   │   ├── taskrun.go              reconcile 본체
│   │   └── resources/pod.go        ★ "Task가 Pod가 되는" 그 코드 — 스텝→컨테이너 매핑
│   └── pipelinerun/            PipelineRun → TaskRun들 생성·DAG 순서 (16의 파이프라인 실행)
├── pkg/pod/                    스텝 순차 실행의 비밀 (entrypoint 주입 — §3)
├── test/                       e2e (실클러스터 대상)
└── config/                     ★ 설치 매니페스트 — ko가 이미지 참조를 치환하는 대상 (19)
```

### 16에서 배운 것 → 소스의 실체

| 16의 지식 | 코드 |
|---|---|
| Task 1개 = Pod 1개, 스텝 = 컨테이너 | reconciler/taskrun/resources/pod.go |
| 스텝이 순서대로 도는 비밀 | pkg/pod의 entrypoint 주입 — 각 컨테이너가 이전 스텝 종료를 대기 |
| PipelineRun의 DAG 실행 | reconciler/pipelinerun — Task 의존 그래프 순회 |
| 파라미터·workspace 전파 | apis의 타입 + reconciler의 변환 로직 |

k8s 컨트롤러 문법(k8s 42~44)이 그대로입니다: informer → reconcile → status 갱신. Knative의 컨트롤러 프레임워크(knative/pkg)를 쓰는 것이 특색 — reconciler 생성이 코드젠 기반입니다.

## 3. 스텝 순차 실행의 내부 — 면접 단골이자 기여 지점

Pod의 컨테이너들은 원래 **동시에** 시작합니다. Tekton은 어떻게 스텝을 순서대로 돌리나요?

```
Tekton이 각 스텝 컨테이너의 entrypoint를 자기 바이너리로 바꿔치기:
  entrypoint 바이너리가 "이전 스텝의 완료 파일"을 기다렸다가 → 원래 명령 실행 → 완료 파일 기록
  → 컨테이너는 전부 떠 있지만, 실제 작업은 릴레이로
```

이 트릭이 pkg/pod와 cmd/entrypoint에 있습니다 — "왜 스텝이 멈춰 있지?"류 이슈의 진원지이자, 소스를 읽은 사람만 진단할 수 있는 영역(26의 _diag와 같은 지위).

## 4. k8s식 프로세스 — 복습이자 실전 (k8s 43)

```
OWNERS      디렉터리별 reviewers/approvers 명단 — 내 PR의 리뷰어가 누구일지 미리 보입니다
/lgtm       리뷰어의 "검토 완료" — Prow가 라벨 부착
/approve    approver의 승인 — lgtm + approve가 모이면 머지 큐로
/ok-to-test 외부 기여자의 PR에 CI 실행 허가 (03의 신뢰 경계가 여기서도!)
/retest     flaky 재실행 (23에서 배운 그 문제의 현장)
```

외부 기여자의 첫 PR은 CI가 자동으로 돌지 않습니다(`/ok-to-test` 대기) — 포크 PR의 신뢰 경계(03)를 커뮤니티 프로세스로 구현한 것. 방치된 것이 아니니 기다리거나 정중히 핑을.

## 5. TEP — 설계 합의의 형식

```
tektoncd/community의 teps/ 디렉터리 — 번호 붙은 마크다운 (k8s KEP의 Tekton판)
형식: Summary / Motivation / Proposal / Alternatives / 상태(proposed→implementable→implemented)
효용 두 가지:
  ① 기여 전 검색 — 내 불편(16의 상처)이 이미 논의됐는지 (중복 이슈 방지 + 맥락 학습)
  ② 설계 교과서 — "왜 이 기능이 이 모양인지"의 1차 사료 (26의 ADR과 같은 지위)
큰 변경 = TEP 먼저. 27의 proposal과 같은 원리, 형식이 더 정형화됨
```

## 6. catalog 기여 — 생산자 경험의 이식 (18의 회수)

```
형식: task/<이름>/<버전>/<이름>.yaml + README + (권장) 테스트
규칙: 파라미터·workspace·results 문서화, 이미지 다이제스트 고정(04!), 최소 권한
심사: OWNERS 리뷰 — 18의 "좋은 액션의 조건"(투명성·최소 권한·버전)과 동일한 기준
효용: YAML+셸만으로 실적·신뢰 축적 → 컨트롤러 기여의 발판
```

18에서 배운 생산자의 책임(입력 검증, 권한 문서화, 안전한 참조)이 그대로 심사 기준입니다 — 커리큘럼의 규율이 생태계 표준과 일치함을 확인하는 지점.

## 7. 소스/도구에서 확인하기

- 기여 가이드: https://github.com/tektoncd/pipeline/blob/main/CONTRIBUTING.md + DEVELOPMENT.md (ko 루프)
- TEP 목록: https://github.com/tektoncd/community/tree/main/teps
- catalog 기여 규칙: https://github.com/tektoncd/catalog — recommendations.md
- Prow 명령: k8s 43 복습 — https://prow.tekton.dev

## 요약 카드

| 질문 | 답 |
|------|----|
| 거버넌스? | CDF 소속 + k8s식 프로세스(OWNERS·Prow·/lgtm) — 세 번째 유형 |
| 개발 루프? | `ko apply -f config/` — 소스→이미지→배포 한 방(19의 합류) |
| 16의 핵심 경로? | reconciler/taskrun + resources/pod.go — "Task가 Pod가 되는" 코드 |
| 스텝 순차의 비밀? | entrypoint 바꿔치기 — 완료 파일 릴레이 (pkg/pod) |
| 큰 변경은? | TEP 먼저 (community/teps) — 기여 전 검색은 예의이자 지름길 |
| 가장 낮은 문? | catalog의 Task 기여 — YAML+셸, 18의 생산자 규율이 심사 기준 |
