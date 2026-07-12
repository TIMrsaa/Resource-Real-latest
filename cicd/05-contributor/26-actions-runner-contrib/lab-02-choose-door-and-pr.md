# Lab 02 — 문 고르기: 4저장소 이슈 탐색, 재현 리포트, 첫 기여

생태계 4저장소의 실제 이슈를 훑고, "통하는 기여"의 형식(재현 저장소 + 진단)을 연습한 뒤, 자기 문으로 첫 기여를 설계합니다.

전제: lab-01 완료, gh CLI.

## Step 1. 4저장소의 온도 측정 — 데이터로 문 고르기

```bash
for R in actions/runner actions/toolkit actions/runner-images actions/actions-runner-controller; do
  OPEN_PR=$(gh api "search/issues?q=repo:$R+is:pr+is:open" -q .total_count)
  MERGED_30D=$(gh api "search/issues?q=repo:$R+is:pr+is:merged+merged:>$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)" -q .total_count)
  GFI=$(gh api "search/issues?q=repo:$R+is:issue+is:open+label:\"good first issue\"" -q .total_count 2>/dev/null || echo "-")
  echo "$R  열린PR:$OPEN_PR  30일머지:$MERGED_30D  good-first-issue:$GFI"
  sleep 2
done
```

예상: runner-images와 ARC의 머지 흐름이 상대적으로 활발하고, runner 본체는 열린 PR 대비 머지가 느린 패턴. ✅ theory §5의 "열림 정도"를 **숫자로** 확인 — 기여처 선택은 감이 아니라 이 온도로.

## Step 2. runner 본체 이슈의 해부 — 좋은 리포트 만나기

```bash
# 유지보수자의 반응을 받은 이슈들에서 "통하는 형식"을 관찰
gh issue list -R actions/runner --limit 10 --json number,title,labels \
  --jq '.[] | "\(.number)  \(.title)  [\([.labels[].name] | join(","))]"'
```

이슈 3개를 골라 열어보고 채점하세요:

```markdown
# 좋은 러너 이슈 체크리스트 (theory §6)
- [ ] 최소 재현 워크플로 (돌려볼 수 있는 YAML)
- [ ] _diag 발췌 (Runner_*.log / Worker_*.log의 해당 구간 — lab-01에서 읽는 법을 배웠습니다)
- [ ] 기대 동작 vs 실제 동작이 한 줄씩
- [ ] 러너 버전·OS·호스티드/셀프호스티드 구분
- [ ] (최상급) 소스의 의심 지점 — "Handlers/X.cs의 이 분기"
★ 유지보수자 응답을 받은 이슈와 무시된 이슈의 차이가 대개 이 목록입니다
```

## Step 3. 재현 리포트 연습 — 25의 Game Day를 기여 형식으로

가상의 버그("composite 액션 안에서 스텝 outputs가 늦게 보인다"고 치자)를 리포트 형식으로 만들어봅니다:

```bash
mkdir -p ~/contrib/repro-demo && cd ~/contrib/repro-demo
cat > repro.md <<'EOF'
## 제목: Composite action outputs not visible to subsequent step under X condition

### 최소 재현
(재현 저장소 링크 — 워크플로 1개 + composite 액션 1개, 20줄 이내)

### 기대 / 실제
- 기대: steps.comp.outputs.value == "hello"
- 실제: 빈 문자열 (러너 2.3xx.x, ubuntu-latest와 self-hosted 모두)

### _diag 발췌
Worker_*.log: CompositeActionHandler가 output을 기록한 시점 vs
StepsRunner가 다음 스텝 컨텍스트를 만든 시점 (타임스탬프 포함 5줄)

### 의심 지점
Runner.Worker/Handlers/CompositeActionHandler.cs 의 output 전파가
ExecutionContext 갱신보다 뒤인 것으로 보임 (lab-01 Step 5의 추적 방법으로 확인)
EOF
echo "→ 이 형식이면 코드 PR 없이도 '기여'다 — 유지보수자의 재현 비용을 0으로 만들었으므로"
```

✅ **재현 비용을 0으로 만드는 것이 리포트 기여의 본질** — eks 27(containers-roadmap 이슈)의 지혜가 실행계 저장소에서도 그대로.

## Step 4. 열린 문 실습 A — toolkit (18의 회수)

```bash
cd ~/contrib && git clone --depth 20 https://github.com/actions/toolkit.git && cd toolkit
ls packages/                              # core, github, exec, cache, artifact ...
# 18에서 쓴 @actions/core의 소스
grep -n "export function setSecret" packages/core/src/core.ts
grep -n "export function getInput" packages/core/src/core.ts

npm install >/dev/null 2>&1 && npm test --workspace=packages/core 2>&1 | tail -5
```

예상: core 패키지 테스트 통과. ✅ 18에서 **소비**한 라이브러리를 이제 테스트까지 돌렸습니다 — TS가 편하다면 여기가 첫 문입니다: `good first issue` 라벨 + 문서·타입 개선 PR이 현실적 시작.

## Step 5. 열린 문 실습 B — runner-images (최저 장벽)

```bash
# 호스티드 러너에 "무엇이 설치돼 있나"의 진실 — 이미지 저장소의 소프트웨어 목록
gh api repos/actions/runner-images/contents/images/ubuntu -q '.[].name' | head -8
echo "---"
echo "기여 형태: 도구 버전 이슈 리포트, 설치 스크립트 수정, 문서 —"
echo "셸 읽을 줄 알면 되는 최저 장벽 + 커뮤니티 기여가 가장 활발한 곳 (theory §5)"
```

## Step 6. 내 문 선언 — 기여 계획서

```markdown
# 나의 첫 기여 계획 (27·28에서도 같은 양식)
- 선택한 문: (runner 진단 / toolkit / runner-images / ARC) — Step 1의 온도 + 내 언어로 근거
- 4주 목표:
  1주: 저장소의 CONTRIBUTING + (runner라면) docs/adrs 정독, 이슈 20개 훑기
  2주: 이슈 하나에 재현/진단 코멘트 (Step 3 형식)
  3주: good first issue 하나 잡아 PR (테스트 포함 — k8s 44)
  4주: 리뷰 대응 완료 (k8s 45의 문법)
- 성공 기준: 머지가 아니라 "유지보수자의 실질 응답을 받는 것" — 특히 runner 본체는
```

## 정리

```bash
bash cleanup.sh
```
