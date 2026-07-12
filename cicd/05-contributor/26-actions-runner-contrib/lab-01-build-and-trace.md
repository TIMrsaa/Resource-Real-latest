# Lab 01 — 소스에서 러너 빌드, 등록, 잡 한 개의 여정 추적

내가 빌드한 러너가 내 저장소의 잡을 실행하게 하고, `_diag`와 소스를 오가며 03의 실행 모델을 코드로 확인합니다.

전제: .NET SDK 8+(`dotnet --version`), git, gh. 메모리 4GB+.

## Step 1. 클론과 빌드 — dev.sh가 진입점

```bash
mkdir -p ~/contrib && cd ~/contrib
git clone --depth 50 https://github.com/actions/runner.git && cd runner

cd src
./dev.sh layout Release 2>&1 | tail -5     # 빌드 + 실행 레이아웃 생성 (수 분)
ls ../_layout/bin | head -5                # Runner.Listener, Runner.Worker 확인
```

예상: `_layout/`에 실행 가능한 러너 완성. ✅ 방금 **잡을 실행하는 그 프로그램**을 소스에서 만들었습니다. `dev.sh`는 `layout`(전체 빌드) / `build`(증분) / `test`(단위 테스트)를 받습니다.

## Step 2. 소스 지도 확인 — 읽기 순서대로

```bash
# theory §2의 읽기 순서: 잡의 여정을 따라
grep -n "class JobDispatcher" Runner.Listener/JobDispatcher.cs | head -2
grep -n "RunAsync" Runner.Worker/JobRunner.cs | head -3
grep -n "class StepsRunner" Runner.Worker/StepsRunner.cs | head -2
ls Runner.Worker/Handlers/ | head -8

# 03의 복선: 시크릿 마스킹의 실체
grep -rn "SecretMasker" Runner.Common/HostContext.cs | head -3
# composite 재귀 한도의 실체 (문서에 없는 답이 코드에)
grep -rn "depth" Runner.Worker/Handlers/CompositeActionHandler.cs | head -3
```

✅ "문서에 없는 질문은 코드가 답한다" — 핸들러 4종과 마스커의 위치를 눈으로 확인했습니다.

## Step 3. 등록 — 내가 빌드한 러너를 내 저장소에

```bash
gh repo create runner-lab --public --clone >/dev/null && cd runner-lab
mkdir -p .github/workflows
cat > .github/workflows/trace.yml <<'EOF'
name: trace
on: [workflow_dispatch]
permissions: { contents: read }
jobs:
  probe:
    runs-on: self-hosted          # ← 내가 빌드한 러너가 잡습니다
    steps:
      - uses: actions/checkout@v4
      - name: run 스텝 (ScriptHandler의 손님)
        run: echo "hello from my own runner build"
      - name: 표현식 치환 관찰
        run: echo "event=${{ github.event_name }}"
EOF
git add -A && git commit -qm "trace workflow" && git push -q
cd ~/contrib/runner/_layout

# 등록 토큰 발급 → 러너 등록 (config.sh의 실체는 Runner.Listener/Configuration)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || gh api user -q '"\(.login)/runner-lab"')
TOKEN=$(gh api -X POST "repos/${REPO}/actions/runners/registration-token" -q .token)
./config.sh --url "https://github.com/${REPO}" --token "$TOKEN" \
  --name my-built-runner --labels self-hosted --unattended
```

⚠️ 08의 규율 그대로: 이 러너는 **내 실습 저장소 전용**입니다 — 퍼블릭 저장소지만 fork PR 트리거가 없는 workflow_dispatch만 쓰므로 안전(실전이면 프라이빗 권장).

## Step 4. 실행과 추적 — Listener의 일기

```bash
./run.sh &                        # Listener 시작 (포그라운드 로그 + _diag 기록)
sleep 10
gh workflow run trace -R "$REPO"
sleep 40

# Listener 일기: 롱폴 → 잡 수신 → Worker 기동
grep -E "Message '.*' received|JobDispatcher|Runner.Worker" _diag/Runner_*.log | tail -5
```

예상: 메시지 수신 → `JobDispatcher` → Worker 프로세스 기동 기록. ✅ theory §1의 ①~③이 로그에 그대로 — **롱폴은 러너가 밖으로 묻는 구조**라서 인바운드 포트가 없습니다(08의 방화벽 논리를 로그로 증명).

## Step 5. Worker의 일기 — 스텝과 핸들러

```bash
# Worker 일기: 잡 준비 → 스텝별 핸들러
grep -E "JobRunner|StepsRunner|ScriptHandler|Handler" _diag/Worker_*.log | tail -10

# run 스텝의 실체: Worker가 만든 임시 스크립트 파일 경로
grep -E "_temp.*\.sh" _diag/Worker_*.log | tail -2
```

예상: checkout(플러그인 경로) → ScriptHandler 두 번(run 스텝 2개). 임시 `.sh` 파일 경로가 보입니다 — **표현식이 이미 치환된 완성 문자열**이 이 파일에 쓰입니다(03의 인젝션이 "구조적"인 이유를 파일 수준에서 확인). ✅ 03의 실행 모델 4층이 전부 소스·로그와 연결됐습니다.

## Step 6. 수정→빌드→확인 루프 — 개발자의 사이클

```bash
cd ~/contrib/runner/src
# 무해한 로그 한 줄 추가 (여정 확인용 — 커밋하지 않습니다)
grep -n "public async Task RunAsync" Runner.Worker/StepsRunner.cs | head -1
# 해당 메서드 초입에 Trace 로그를 추가해보세요 (예: context.Debug($"[mine] step count..."))
# 그 후:
./dev.sh build Release 2>&1 | tail -2
cd ../_layout && ./run.sh &
gh workflow run trace -R "$REPO" && sleep 40
grep "\[mine\]" _diag/Worker_*.log | head -2 && echo "→ 내 코드가 러너 안에서 돌았다 ✅"
git -C ~/contrib/runner checkout -- src/   # 실험 원복
```

✅ **수정→빌드→실행→로그 확인**의 루프가 손에 붙었습니다 — 기여의 물리적 기초. eks 28의 "로컬 컨트롤러를 실클러스터에 물리는" 사이클과 동형입니다.

## Step 7. 정리(러너 등록 해제는 여기서)

```bash
kill %1 2>/dev/null || true
TOKEN=$(gh api -X POST "repos/${REPO}/actions/runners/remove-token" -q .token)
cd ~/contrib/runner/_layout && ./config.sh remove --token "$TOKEN"
```

lab-02에서 이슈 탐색과 기여 전략으로 이어집니다. 클론은 유지.
