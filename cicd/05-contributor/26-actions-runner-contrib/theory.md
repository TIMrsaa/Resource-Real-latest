# 이론 — 러너 해부: Listener/Worker, 잡 메시지의 여정, 핸들러, 생태계 지도

> **🌱 17세 눈높이 비유: 콜센터 상담원의 하루**
> - **Runner.Listener** = 헤드셋을 끼고 대기하는 접수원 — 본사(GitHub Actions 서비스)에 "일 있어요?"를 계속 묻습니다(롱폴). 전화가 없으면 50초쯤 기다렸다 다시 묻습니다
> - **잡 메시지** = 본사가 내려주는 업무 지시서 — 암호화되어 있고, 이 상담소만 열 수 있습니다
> - **Runner.Worker** = 지시서를 받으면 **새로 출근하는 전문 상담원** — 한 건만 처리하고 퇴근합니다(잡마다 새 프로세스 — 03의 "잡마다 새 러너"의 실체)
> - **핸들러** = 상담 매뉴얼의 종류 — 일반 문의(run 스텝), 전문 상담(node 액션), 외부 연결(docker 액션), 매뉴얼 묶음(composite)
> - **_diag 로그** = 상담소의 CCTV — 고객용 통화 기록(잡 로그)과 별개로, 상담소 내부의 모든 동작이 남습니다
> - **자동 업데이트** = 본사가 "새 매뉴얼 버전 받으세요"라고 하면 접수원이 스스로 교체됩니다

---

## 1. 큰 그림 — 2프로세스와 메시지의 여정

```
GitHub Actions 서비스 (제어면 — 우리는 볼 수 없음)
        ▲ ① 롱폴 (HTTPS — 러너가 밖으로 접속. 인바운드 포트 없음 — 08의 방화벽 논리)
        │ ② 잡 메시지 (러너 키로 암호화)
┌───────┴────────┐   ③ 프로세스 생성   ┌────────────────┐
│ Runner.Listener │ ─────────────────▶ │ Runner.Worker  │ (잡 1개 = Worker 1개)
│  대기·수신·관리  │                    │ 스텝 실행 엔진   │
└────────────────┘                    └───┬────────────┘
                                          │ ④ 스텝별 핸들러 실행 → 로그 실시간 업로드
                                          ▼
                              ScriptHandler / NodeScriptActionHandler /
                              ContainerActionHandler / CompositeActionHandler
```

- **아웃바운드 전용**: 러너가 서비스로 접속합니다(반대 없음) — self-hosted가 방화벽 안에서 동작하는 이유(08)
- **Worker 격리**: 잡마다 새 Worker 프로세스 — 03의 "잡 간 격리"의 구현 지점. ephemeral 러너(08)는 여기에 "한 잡 후 Listener까지 종료"를 더한 것
- 혈통: Azure Pipelines 에이전트의 후손 — 소스 곳곳의 `DistributedTask` 네임스페이스가 그 흔적

## 2. 소스 지도 — 어디에 무엇이 있나

```
actions/runner
├── src/
│   ├── Runner.Listener/        ← 대기·등록·잡 수신
│   │   ├── MessageListener.cs      세션 생성·롱폴 루프
│   │   ├── JobDispatcher.cs        잡 메시지 → Worker 프로세스 기동
│   │   └── Configuration/          config.sh의 실체 (등록 토큰 → 러너 등록)
│   ├── Runner.Worker/           ← 잡 실행 엔진 (이 모듈의 심장)
│   │   ├── JobRunner.cs            잡 수명주기 (준비 → 스텝들 → 정리)
│   │   ├── StepsRunner.cs          스텝 순회 — if 조건 평가, continue-on-error 처리
│   │   ├── ExecutionContext.cs     로그·상태·표현식 컨텍스트 (steps.*, env.* 가 사는 곳)
│   │   └── Handlers/               ★ 스텝 종류별 실행기
│   │       ├── ScriptHandler.cs        run: — 셸 선택·스크립트 파일 생성·실행
│   │       ├── NodeScriptActionHandler.cs  JS 액션(18에서 만든 것)을 node로
│   │       ├── ContainerActionHandler.cs   Docker 액션 — 이미지 빌드/pull·docker run
│   │       └── CompositeActionHandler.cs   composite — 스텝 목록을 재귀 실행
│   ├── Runner.Common/           ← 공용: HostContext, 로깅(_diag), 서비스 클라이언트
│   ├── Runner.Sdk/              ← 프로세스 실행(ProcessInvoker) 등 저수준
│   ├── Runner.Plugins/          ← checkout 등 내장 플러그인 (actions/checkout의 빠른 경로)
│   └── Test/                    ← xUnit 테스트 (L0 = 단위)
├── docs/adrs/                   ← ★ 설계 결정 기록 — "왜 이렇게 만들었나"의 1차 사료
└── dev.sh / dev.cmd             ← 빌드 진입점 (layout/build/test)
```

읽기 순서 추천: `JobDispatcher`(잡이 오면) → `JobRunner`(잡이 시작되면) → `StepsRunner`(스텝을 돌면) → 핸들러 하나(`ScriptHandler`) — 이 네 파일이 03의 실행 모델 전부를 코드로 보여줍니다.

## 3. 03의 지식이 코드가 되는 지점들

| 03에서 배운 것 | 소스의 실체 |
|---|---|
| 표현식은 셸 파싱 전에 치환 | 서버·러너의 표현식 평가 후 ScriptHandler가 **완성된 문자열**을 스크립트 파일로 씀 — 인젝션의 구조적 원인 |
| 시크릿 마스킹 | HostContext의 SecretMasker — 로그 파이프라인에서 등록된 값을 치환(문자열 기반 — 인코딩 우회가 뚫는 이유) |
| 잡마다 새 환경 | JobDispatcher가 잡마다 Worker 프로세스 생성, ephemeral이면 Listener 종료 |
| GITHUB_TOKEN 주입 | 잡 메시지에 포함되어 Worker로 — 잡 끝나면 만료(22의 단명 원리) |
| checkout이 빠른 이유 | Runner.Plugins의 내장 플러그인 경로 (일반 액션보다 가까움) |
| composite 재귀 | CompositeActionHandler가 스텝 목록을 StepsRunner로 재귀 — 중첩 한도도 여기 |

## 4. _diag — 러너 개발자의 눈

```
_diag/Runner_*.log    Listener의 일기: 세션, 롱폴, 잡 수신, 업데이트
_diag/Worker_*.log    Worker의 일기: 잡 준비, 스텝별 핸들러, 컨테이너 기동, 종료 코드
잡 로그(웹 UI)        고객용 — 스텝의 stdout/stderr만
```

25의 러너 트러블슈팅이 여기서 소스와 만납니다: "잡이 안 잡힌다" → Runner 로그의 롱폴 응답을, "스텝이 이상하게 죽는다" → Worker 로그의 핸들러 준비 과정을 봅니다. **이슈를 열 때 _diag 발췌를 붙이는 것**이 이 저장소에서 가장 환영받는 리포트 형식입니다.

## 5. 생태계 4저장소 — 기여의 문 고르기

| 저장소 | 언어 | 무엇 | 열림 정도 | 맞는 사람 |
|---|---|---|---|---|
| actions/runner | C# | 러너 본체 | ▲ 로드맵 중심, 외부 기능 PR 보수적 | 진단·이슈 품질로 기여 |
| **actions/toolkit** | TS | @actions/core 등 라이브러리(18) | ○ 라이브러리라 상대적으로 열림 | 18을 지난 JS 개발자 — **추천 첫 문** |
| **actions/runner-images** | 셸/PS | 호스티드 러너 VM 이미지 | ◎ 커뮤니티 기여 가장 활발 | 도구 추가·버전 이슈 — 진입 장벽 최저 |
| actions/actions-runner-controller | Go | ARC(08의 그것) | ○ K8s 오퍼레이터 문법 | k8s 42~44를 지난 Go 개발자 |

판정 기준은 eks 28의 "내 변경이 어느 쪽인가"와 동형입니다: 스텝 실행의 동작 → runner, 액션 작성 경험 → toolkit, "러너에 X가 설치돼 있으면" → runner-images, 러너의 K8s 스케일링 → ARC.

## 6. 기업 주도 저장소의 기여 전략

```
통하는 것: 재현 저장소가 딸린 버그 리포트 (최소 재현 워크플로 + _diag 발췌 + 기대/실제)
          정확한 진단이 담긴 이슈 ("Handlers/ScriptHandler.cs의 이 분기에서...")
          문서·주석 수정, toolkit·runner-images·ARC의 코드 PR
어려운 것: 본체의 새 기능 PR (로드맵 밖이면 오래 방치될 수 있음 — 감정 소모 주의)
지혜:      큰 기능은 이슈로 제안해 방향 확인 후 코드 (k8s 45의 "PR보다 합의 먼저"와 동일)
          ADR(docs/adrs)을 먼저 읽기 — "왜 안 그렇게 했는지"가 이미 기록된 경우가 많습니다
```

## 7. 소스/도구에서 확인하기

- 저장소: https://github.com/actions/runner — `docs/contribute.md`, `docs/adrs/`
- toolkit: https://github.com/actions/toolkit / runner-images: https://github.com/actions/runner-images
- ARC: https://github.com/actions/actions-runner-controller
- 러너 프로토콜 관찰: lab-01의 `_diag` — 공식 프로토콜 문서는 없습니다(서비스가 비공개), 로그가 최고의 문서

## 요약 카드

| 질문 | 답 |
|------|----|
| 2프로세스? | Listener(롱폴 대기·잡 수신) + Worker(잡 1개 실행 후 종료 — 격리의 실체) |
| 통신 방향? | 러너 → 서비스 아웃바운드 전용 (방화벽 안 동작의 이유 — 08) |
| 스텝 실행? | StepsRunner가 순회, 종류별 핸들러(Script/Node/Container/Composite) |
| 개발자의 눈? | `_diag/` — Runner(Listener 일기) + Worker(잡 실행 일기) |
| 기여의 문 4개? | runner(C#·진단), toolkit(TS·추천), runner-images(최저 장벽), ARC(Go·K8s) |
| 본체 기여 전략? | 재현+진단 이슈가 코드 PR보다 잘 통합니다 — 로드맵 밖 기능 PR은 합의 먼저 |
