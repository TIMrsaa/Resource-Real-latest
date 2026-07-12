# Lab 02 — affected를 CI로: 동적 매트릭스, required check 게이트

lab-01의 affected 계산을 GHA에 통합합니다 — 06의 동적 매트릭스와 03의 `ci` 게이트가 모노레포에서 합류합니다.

전제: lab-01의 저장소(~/ci-lab/mono), gh CLI.

## Step 1. affected → 동적 매트릭스 워크플로

```bash
cd ~/ci-lab/mono
mkdir -p .github/workflows
cat > .github/workflows/mono-ci.yml <<'EOF'
name: mono-ci
on:
  pull_request:
  workflow_dispatch:
permissions: { contents: read }

jobs:
  detect:
    runs-on: ubuntu-latest
    outputs:
      projects: ${{ steps.aff.outputs.projects }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }          # ★ affected는 base와의 diff가 필요 — 얕은 클론이면 계산 불가
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - id: aff
        name: affected 계산 (base 대비)
        run: |
          BASE="${{ github.event.pull_request.base.sha || 'HEAD~1' }}"
          PROJECTS=$(npx turbo ls --affected --output=json 2>/dev/null \
            | jq -c '[.packages.items[].name]' || echo '[]')
          echo "projects=$PROJECTS" >> "$GITHUB_OUTPUT"
          echo "affected: $PROJECTS"
        env:
          TURBO_SCM_BASE: ${{ github.event.pull_request.base.sha }}

  test:
    needs: detect
    if: needs.detect.outputs.projects != '[]'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        project: ${{ fromJSON(needs.detect.outputs.projects) }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - name: ${{ matrix.project }} 테스트
        run: npx turbo run test --filter=${{ matrix.project }}

  ci:                                     # ★ 03의 게이트 — required check는 이것 하나
    needs: [detect, test]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: 게이트 판정 (스킵은 통과, 실패만 차단)
        run: |
          echo "detect=${{ needs.detect.result }} test=${{ needs.test.result }}"
          [[ "${{ needs.detect.result }}" == "success" ]] || exit 1
          [[ "${{ needs.test.result }}" == "success" || "${{ needs.test.result }}" == "skipped" ]] || exit 1
          echo "✅ gate pass"
EOF

git add -A && git commit -qm "ci: affected matrix + gate"
gh repo create cicd-lab-mono --public --source=. --push >/dev/null
```

포인트 세 가지: ① `fetch-depth: 0` — affected는 base 커밋과의 diff라서 얕은 클론이면 계산이 안 됩니다(흔한 첫 실패). ② 매트릭스가 **affected 목록에서 동적 생성**(06). ③ `ci` 잡이 `if: always()`로 스킵까지 판정.

## Step 2. 시나리오 A — api만 바꾼 PR

```bash
git checkout -qb change-api
echo "// api change" >> services/api/test.js
git add -A && git commit -qm "fix(api): tweak" && git push -qu origin change-api
gh pr create --title "api only" --body "affected should be api only" >/dev/null
sleep 90
gh pr checks 2>/dev/null || gh run view --log 2>/dev/null | grep -E "affected:|테스트|gate"
```

예상: `affected: ["@mono/api"]` — test 매트릭스는 api 1건만, web·shared는 잡 자체가 없습니다. ✅ 커밋이 작으면 CI도 작습니다 — 피드백 루프(01) 보존.

## Step 3. 시나리오 B — shared를 바꾼 PR (전이 의존)

```bash
git checkout -q main && git checkout -qb change-shared
sed -i "s/Hello/Howdy/" libs/shared/index.js
git add -A && git commit -qm "feat(shared): howdy" && git push -qu origin change-shared
gh pr create --title "shared change" --body "affected should include api, web" >/dev/null
sleep 90
gh run list --limit 1
gh run view --log 2>/dev/null | grep -E "affected:" | head -2
```

예상: `affected: ["@mono/shared","@mono/api","@mono/web"]` — 매트릭스 3건, api/web 테스트 실패(형식 변경). ✅ lab-01 Step 2의 침묵의 회귀가 **PR 단계에서 차단**됩니다.

## Step 4. required check 함정 재현 — 그리고 게이트가 답인 이유

브랜치 보호에 무엇을 required로 걸어야 하나요? 잘못된 답을 먼저 보자:

```bash
# (실험) 만약 "test (@mono/web)"을 required check로 걸었다면:
#   시나리오 A(api만 변경)에서 그 잡은 생성조차 안 됨
#   → GitHub은 "expected — waiting for status" 로 영원히 대기
#   → api만 고친 무고한 PR이 머지 불가 ❌
echo "매트릭스 잡 이름은 required check로 걸 수 없습니다 — 목록이 동적이므로"

# 옳은 답: ci 게이트 하나만 required로
gh api -X PUT "repos/{owner}/{repo}/branches/main/protection" \
  --input - <<'EOF' >/dev/null 2>&1 || echo "(브랜치 보호는 퍼블릭/유료 플랜에서만 — 개념 확인으로 충분)"
{ "required_status_checks": { "strict": false, "contexts": ["ci"] },
  "enforce_admins": false, "required_pull_request_reviews": null, "restrictions": null }
EOF
echo "required check = 'ci' 단 하나 — 매트릭스가 어떻게 변해도 불변"
```

✅ **스킵은 통과가 아닙니다**(theory §6) — 동적 매트릭스와 브랜치 보호(02)를 함께 쓰려면 판정을 단일 `ci` 잡으로 모아야 합니다. 03에서 만든 게이트 패턴이 모노레포에서 구조적 필수가 되는 순간.

## Step 5. 배포 매핑 스케치 — affected의 끝

```markdown
# affected → 배포 (14의 GitOps와 연결)
detect (affected: [api]) 
  → build: api 이미지만 빌드·push (태그 = SHA, 다이제스트 기록 — 04)
  → gitops 저장소의 apps/api/kustomization.yaml만 갱신 (newTag)
  → ArgoCD ApplicationSet(14)이 api 앱만 OutOfSync → sync
  → web·shared 소비자든 아니든, 안 바뀐 서비스는 배포 이벤트 자체가 없음
★ 저장소는 하나, 배포 단위는 그래프가 정합니다
```

## Step 6. 산출물 — 모노레포 CI 설계 결정표

```markdown
# 모노레포 CI 체크리스트
- [ ] affected 계산: 그래프 기반 (path filter는 독립 폴더에만)
- [ ] fetch-depth: 0 (base와의 diff 필요)
- [ ] 매트릭스: affected 목록에서 동적 생성 (06)
- [ ] required check: 단일 ci 게이트 (매트릭스 잡 이름 금지)
- [ ] 캐시: 태스크 입력 정직하게 선언 + 원격 캐시 (팀 공유)
- [ ] 루트 설정 변경 = 전체 실행 감수 (globalDependencies)
- [ ] 그래프 밖 의존(API 계약)은 계약 테스트로 (05)
```

## 정리

```bash
bash cleanup.sh
```
