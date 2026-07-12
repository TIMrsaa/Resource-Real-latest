# Lab 02 — 승인 게이트와 동적 매트릭스

01에서 "Continuous Delivery = 배포 버튼은 사람이 누른다"고 했습니다. 그 버튼을 만듭니다 — 그리고 프로덕션 시크릿이 PR CI에서는 **보이지 않는** 것을 확인합니다.

```bash
cd ~/ci-lab/consumer
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

## Step 1. 환경 두 개와 각자의 시크릿

```bash
# staging: 보호 없음 (자동 배포)
gh api -X PUT "repos/$REPO/environments/staging" >/dev/null

# production: 승인 필요 + main 브랜치만
ME=$(gh api user -q .id)
gh api -X PUT "repos/$REPO/environments/production" \
  -F "wait_timer=0" \
  -F "reviewers[][type]=User" -F "reviewers[][id]=$ME" \
  -F "deployment_branch_policy[protected_branches]=true" \
  -F "deployment_branch_policy[custom_branch_policies]=false" >/dev/null

# 환경별 시크릿 — 이 환경의 잡에서만 읽힙니다
gh secret set DEPLOY_TOKEN --env staging    --body "staging-token-abc"
gh secret set DEPLOY_TOKEN --env production --body "PRODUCTION-token-xyz"

gh api "repos/$REPO/environments" -q '.environments[] | {name: .name, rules: [.protection_rules[].type]}'
```

## Step 2. 배포 워크플로 — 승격 파이프라인 (01의 승격 모델)

```bash
cat > .github/workflows/deploy.yml <<'EOF'
name: deploy
on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.fake.outputs.digest }}
    steps:
      - uses: actions/checkout@v4
      - id: fake
        name: 빌드 (04에서 진짜 이미지를 만들었습니다)
        run: echo "digest=sha256:$(echo -n $GITHUB_SHA | sha256sum | cut -c1-64)" >> "$GITHUB_OUTPUT"

      - name: PR CI 컨텍스트에는 프로덕션 시크릿이 없습니다
        run: |
          if [ -z "${{ secrets.DEPLOY_TOKEN }}" ]; then
            echo "✅ 이 잡(환경 없음)에는 DEPLOY_TOKEN이 없다"
          else
            echo "🚨 노출됨"
          fi

  staging:
    needs: build
    environment:
      name: staging
      url: https://staging.example.com
    runs-on: ubuntu-latest
    steps:
      - name: 스테이징 배포 (승인 없이 자동)
        run: |
          echo "배포: ${{ needs.build.outputs.digest }}"
          echo "토큰 앞 7자: $(echo '${{ secrets.DEPLOY_TOKEN }}' | cut -c1-7)"   # staging-...

  production:
    needs: staging                 # ★ 스테이징을 지나야 프로덕션 (승격)
    environment:
      name: production
      url: https://app.example.com
    runs-on: ubuntu-latest
    steps:
      - name: 프로덕션 배포 (승인 후에만 실행됨)
        run: |
          echo "같은 아티팩트를 승격: ${{ needs.build.outputs.digest }}"
          echo "토큰 앞 10자: $(echo '${{ secrets.DEPLOY_TOKEN }}' | cut -c1-10)"  # PRODUCTION-...
EOF
git add -A && git commit -qm "ci: deploy pipeline with environments" && git push -q
```

## Step 3. 승인 게이트가 실제로 멈추는지

```bash
sleep 60
gh run list --workflow=deploy --limit 1
gh run view --json jobs -q '.jobs[] | {name: .name, status: .status, conclusion: .conclusion}' 2>/dev/null
```

예상: `build`, `staging`은 완료 — `production`은 **`waiting`**. ✅ 러너를 점유하지 않은 채 사람의 승인을 기다립니다.

```bash
# 승인 (CLI 또는 웹 UI)
RUN_ID=$(gh run list --workflow=deploy --limit 1 --json databaseId -q '.[0].databaseId')
gh api -X POST "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" \
  -F "environment_ids[]=$(gh api "repos/$REPO/environments/production" -q .id)" \
  -f state=approved -f comment="배포 승인 — 스테이징 검증 완료" >/dev/null
sleep 30
gh run view $RUN_ID --log 2>/dev/null | grep -E "같은 아티팩트|PRODUCTION-" | head -2
```

✅ 세 가지를 확인했습니다:

1. **승인 전까지 대기**(비용 0) — 01의 "배포 버튼"
2. **같은 다이제스트가 승격**됩니다 — 04의 아티팩트 불변성
3. `build` 잡(환경 없음)은 `DEPLOY_TOKEN`을 못 읽었고, 각 환경 잡은 **자기 환경의 값**을 읽었습니다

## Step 4. 브랜치 정책 — main이 아니면 프로덕션 배포 불가

```bash
git checkout -q -b hotfix/try-prod
git commit -q --allow-empty -m "try deploy from branch" && git push -qu origin hotfix/try-prod
gh workflow run deploy.yml --ref hotfix/try-prod 2>&1 | tail -1
sleep 40
gh run list --workflow=deploy --limit 1 --json headBranch,conclusion,status
gh run view --log-failed 2>/dev/null | grep -i "branch.*not allowed\|not permitted" | head -1 \
  || echo "(production 잡이 브랜치 정책으로 거부됨 — UI에서 확인)"
git checkout -q main && git push -q origin --delete hotfix/try-prod 2>/dev/null || true
```

✅ `deployment_branch_policy`가 **워크플로 코드가 아니라 저장소 설정**에서 강제합니다 — 워크플로를 고칠 수 있는 사람도 이 규칙은 못 우회합니다(24의 컴플라이언스 논의로 이어집니다).

## Step 5. 동적 매트릭스 — 20(모노레포)의 씨앗

```bash
mkdir -p services/{api,worker,web}
for s in api worker web; do echo "print('$s')" > services/$s/main.py; done

cat > .github/workflows/dynamic.yml <<'EOF'
name: dynamic-matrix
on: [push, workflow_dispatch]
permissions: { contents: read }

jobs:
  discover:
    runs-on: ubuntu-latest
    outputs:
      services: ${{ steps.d.outputs.services }}
      count: ${{ steps.d.outputs.count }}
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 2 }
      - id: d
        name: 변경된 서비스만 골라냅니다
        run: |
          CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | grep '^services/' | cut -d/ -f2 | sort -u || true)
          [ -z "$CHANGED" ] && CHANGED=$(ls services)     # 첫 커밋 등: 전부
          JSON=$(echo "$CHANGED" | jq -R -s -c 'split("\n") | map(select(length>0))')
          echo "services=$JSON" >> "$GITHUB_OUTPUT"
          echo "count=$(echo "$JSON" | jq 'length')" >> "$GITHUB_OUTPUT"
          echo "빌드 대상: $JSON"

  build:
    needs: discover
    if: needs.discover.outputs.count != '0'      # ★ 빈 매트릭스 방어 (theory §4)
    strategy:
      fail-fast: false
      matrix:
        service: ${{ fromJSON(needs.discover.outputs.services) }}
    runs-on: ubuntu-latest
    steps:
      - run: echo "building ${{ matrix.service }}"

  ci:
    if: always()
    needs: [discover, build]
    runs-on: ubuntu-latest
    steps:
      - name: 빌드가 skip이어도 게이트는 통과 (변경 없음)
        run: |
          R="${{ needs.build.result }}"
          [ "$R" = "success" ] || [ "$R" = "skipped" ]
EOF
git add -A && git commit -qm "ci: dynamic matrix over services" && git push -q
sleep 70
gh run view --log 2>/dev/null | grep -E "빌드 대상|building " | head -5
```

✅ **매트릭스가 코드로 계산됩니다.** 하나의 서비스만 바뀌면 하나의 잡만 돕니다 — 모노레포 CI 시간의 핵심 최적화이고, 20에서 Bazel/Nx 수준으로 정교화됩니다.

⚠️ `count == 0`일 때의 `if:` 방어를 빼면 — build 잡이 아예 생성되지 않아 `needs`가 skipped가 되고, 수렴 잡의 `[ "$R" = "success" ]`가 실패합니다. 03의 게이트 패턴이 여기서 `skipped` 허용까지 확장됐습니다.

## Step 6. 산출물 — 배포 통제 문서

```markdown
# 배포 통제 (environments)
| 환경 | 승인 | 브랜치 정책 | 시크릿 | 배포 방식 |
|------|------|-----------|--------|----------|
| staging | 없음 | 제한 없음 | staging 전용 | main push 시 자동 |
| production | 리뷰어 1명 | protected(main)만 | production 전용 | staging 성공 후 승인 |

## 성질
- 승인 대기 중 러너 미점유 (비용 0, 며칠 대기 가능)
- 프로덕션 시크릿은 production 환경 잡에서만 — PR CI에서 접근 불가(03의 포크 위험 차단)
- 브랜치 정책은 저장소 설정에서 강제 — 워크플로 수정으로 우회 불가

## 승격 규율 (01·04)
- build는 1회, 다이제스트를 outputs로 → staging → production이 **같은 다이제스트** 사용
- 환경 차이는 environment variables/secrets로만
```

## 정리

```bash
bash cleanup.sh
```
