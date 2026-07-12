# Lab 01 — 승인 게이트·SoD·추적성, 그리고 감사관에게 내밀 리포트

컴플라이언스 3요소(추적성·승인·불변 기록)를 게이트로 구현하고, 실행 이력에서 감사 리포트를 뽑습니다.

전제: gh CLI. (조직 기능 일부는 개인 계정에서 제한 — 개념은 동일하게 확인됩니다)

## Step 1. 추적성 게이트 — 티켓 없는 변경은 머지 불가

```bash
mkdir -p ~/ci-lab/enterprise/.github/workflows && cd ~/ci-lab/enterprise
git init -q . && git config user.email l@e.com && git config user.name L
echo "v1" > app.txt

cat > .github/workflows/traceability.yml <<'EOF'
name: traceability
on: [pull_request]
permissions: { contents: read }
jobs:
  ticket-link:
    runs-on: ubuntu-latest
    steps:
      - name: PR 본문에 티켓 링크 필수 (컴플라이언스 ①추적성)
        run: |
          BODY=$(cat <<'PRBODY'
          ${{ github.event.pull_request.body }}
          PRBODY
          )
          echo "$BODY" | grep -qE "(JIRA|TICKET|ISSUE)-[0-9]+" || {
            echo "🚨 티켓 참조 없음 — 'TICKET-123' 형식을 PR 본문에"; exit 1; }
          echo "✅ 추적성: 변경 ↔ 티켓 연결됨"
EOF

git add -A && git commit -qm "init"
gh repo create cicd-lab-enterprise --public --source=. --push >/dev/null
```

검증 — 티켓 없는 PR과 있는 PR:

```bash
git checkout -qb no-ticket && echo v2 > app.txt && git add -A && git commit -qm "change"
git push -qu origin no-ticket
gh pr create --title "no ticket" --body "그냥 바꿈" >/dev/null && sleep 45
gh pr checks 2>/dev/null | head -3          # 예상: traceability 실패 ❌

gh pr edit --body "TICKET-4821: 요구사항에 따른 변경" && sleep 5
gh pr close no-ticket -d 2>/dev/null || true
```

✅ "커밋 → 티켓" 체인이 문서 규정이 아니라 **머지 차단 게이트**가 됐습니다(Compliance as Code). 실전은 PR 제목 규칙 + 브랜치 보호의 required check(03의 `ci` 게이트에 포함)로.

## Step 2. 승인 게이트 + SoD — environment로

```bash
git checkout -q main
cat > .github/workflows/deploy.yml <<'EOF'
name: deploy
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment: production          # ★ 승인 게이트가 여기 걸립니다
    steps:
      - uses: actions/checkout@v4
      - name: 배포 기록 (감사의 재료 — 다이제스트까지)
        run: |
          echo "deploy sha=$(git rev-parse HEAD)"
          echo "artifact-digest=sha256:$(git rev-parse HEAD | sha256sum | cut -c1-16)..."
EOF

# environment 생성 + 승인자 지정 + 자기승인 금지 (SoD)
gh api -X PUT "repos/{owner}/{repo}/environments/production" --input - <<EOF >/dev/null
{
  "reviewers": [{ "type": "User", "id": $(gh api user -q .id) }],
  "prevent_self_review": true,
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
EOF
gh api -X POST "repos/{owner}/{repo}/environments/production/deployment-branch-policies" \
  -f name="main" >/dev/null 2>&1 || true

git add -A && git commit -qm "deploy with approval gate" && git push -q
sleep 20
gh run list --workflow=deploy --limit 1
```

예상: 런이 **waiting** 상태 — 승인 전까지 배포가 멈춰 있습니다. ✅ 두 가지가 걸렸습니다: ① 사람 승인(위험 등급별 — prod에만) ② `prevent_self_review` — **변경 작성자가 자기 배포를 승인할 수 없음**(SoD). 개인 계정 실습에서는 승인자가 본인뿐이라 이 런은 대기로 남습니다 — 실조직에서는 별도 승인자 그룹:

```bash
gh run cancel $(gh run list --workflow=deploy --limit 1 --json databaseId -q '.[0].databaseId') 2>/dev/null || true
echo "SoD 확인: 작성자 = 승인자인 배포는 구조적으로 불가"
```

## Step 3. 고무도장 방지 — 승인자에게 판단 재료를

```bash
cat > .github/workflows/approval-context.yml <<'EOF'
name: approval-context
on: [pull_request]
permissions: { contents: read, pull-requests: write }
jobs:
  summarize:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: 승인 판단 재료 자동 생성
        run: |
          {
            echo "## 승인 참고 (자동 생성)"
            echo "- 변경 파일: $(git diff --name-only origin/main...HEAD | wc -l)개"
            echo "- 변경 영역: $(git diff --name-only origin/main...HEAD | cut -d/ -f1 | sort -u | tr '\n' ' ')"
            echo "- diff 크기: +$(git diff --shortstat origin/main...HEAD | grep -oE '[0-9]+ insertion' | cut -d' ' -f1 || echo 0)"
            echo "- 롤백: revert 커밋으로 가능 (스키마 변경 없음 여부는 diff의 migrations/ 참조)"
          } > summary.md
          cat summary.md
      - uses: marocchino/sticky-pull-request-comment@v2
        with: { path: summary.md }
        continue-on-error: true
EOF
git add -A && git commit -qm "approval context" && git push -q
```

✅ 승인의 품질은 **요청의 설계**가 정합니다(theory §1) — 승인자가 diff 800줄이 아니라 요약·영향 범위·롤백 계획을 보게. 실전에서는 affected(20)·테스트 결과·SLO 현황(23)까지 붙입니다.

## Step 4. 감사 리포트 — "누가 무엇을 언제, 어떤 다이제스트로"

```bash
gh api "repos/{owner}/{repo}/actions/runs?per_page=30" --jq '
  [.workflow_runs[] | select(.name=="deploy")] |
  map({
    when: .created_at,
    who: .actor.login,
    what_sha: .head_sha[0:12],
    trigger: .event,
    status: .conclusion,
    workflow_at: .path
  })' > audit-report.json
python3 -m json.tool audit-report.json | head -20

cat <<'EOF'
감사관 질문 → 리포트 매핑:
  "3월 prod 배포 목록"        → when + status 필터
  "이 배포는 누가 승인?"       → environment 승인 이력 (gh api .../approvals)
  "이 바이너리의 출처?"        → what_sha → 커밋 → PR → 티켓 (Step 1의 체인)
  "기록 조작 가능성?"          → 로그는 플랫폼 보관 + 외부 적재(불변성) + Rekor(21)
EOF
```

✅ 감사 대응이 "2주간 증빙 수집"이 아니라 **스크립트 실행**이 됩니다 — 단 불변성 요건: 이 데이터를 저장소 관리자가 지울 수 있으므로, 실조직은 주기 배치(23)로 **별도 계정의 스토리지에 적재**합니다(CloudTrail의 교차 계정 S3와 같은 원리).

## Step 5. break-glass 설계 — 우회로를 양지로

```markdown
# 긴급 배포 경로 (금지하면 몰래 합니다 — theory §6)
- 별도 워크플로 (workflow_dispatch + 'emergency' environment)
- 승인 1인으로 축소 하되: 사유 입력 필수(inputs.reason)
- 실행 시 자동으로: ① 감사 태그 ② 사후 리뷰 이슈 생성 ③ 23의 지표에 카운트
- 월간 리뷰: break-glass 사용 횟수가 늘면 정상 경로가 불편하다는 신호
```

## 정리

lab-02에서 이 저장소에 정책 게이트를 추가합니다. 유지.
