# Lab 02 — 게이트를 물리적으로: 브랜치 보호와 리뷰 시간 측정

01의 "신뢰의 게이트"가 GitHub에서 어떻게 강제되는지 직접 걸어보고, 리드 타임에서 리뷰가 차지하는 비중을 **실측**합니다.

## Step 1. 실험 저장소

```bash
mkdir -p ~/ci-lab/protect && cd ~/ci-lab/protect
git init -q && git config user.email l@e.com && git config user.name L
echo "# demo" > README.md && git add -A && git commit -qm "init" && git branch -M main

gh repo create cicd-lab-protect --private --source=. --push
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "repo: $REPO"
```

## Step 2. 아무 보호도 없을 때 — 게이트의 부재

```bash
echo "bad code" >> README.md && git commit -qam "직접 push" && git push -q
git log --oneline -1
```

리뷰도, CI도, 흔적도 없이 main이 바뀌었습니다. 프로덕션이 main이라면(GitHub flow) **방금 검증되지 않은 것이 배포됐습니다**.

```bash
git reset -q --hard HEAD~1 && git push -qf   # 되돌리기 (force-push도 가능하다는 것 자체가 문제)
```

## Step 3. 보호 규칙 걸기 (theory §6)

```bash
gh api -X PUT "repos/$REPO/branches/main/protection" \
  -H "Accept: application/vnd.github+json" \
  -f "required_status_checks[strict]=true" \
  -F "required_status_checks[contexts][]=ci" \
  -F "enforce_admins=true" \
  -f "required_pull_request_reviews[required_approving_review_count]=1" \
  -f "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  -F "restrictions=null" \
  -F "allow_force_pushes=false" \
  -F "allow_deletions=false"

gh api "repos/$REPO/branches/main/protection" -q '{
  reviews: .required_pull_request_reviews.required_approving_review_count,
  strict: .required_status_checks.strict,
  admins: .enforce_admins.enabled,
  force_push: .allow_force_pushes.enabled }'
```

이제 직접 push를 시도하면:

```bash
echo "sneaky" >> README.md && git commit -qam "직접 push 재시도"
git push 2>&1 | tail -3
```

예상: `protected branch hook declined` — ✅ **게이트가 물리적 실체를 얻었습니다.** `enforce_admins=true`가 핵심입니다: 예외를 만들면 그 예외가 규칙이 됩니다(pitfalls 2).

```bash
git reset -q --hard origin/main
```

## Step 4. 머지 방식의 차이를 히스토리로 확인

```bash
# 세 커밋짜리 브랜치
git checkout -q -b feat/three
for i in 1 2 3; do echo "step $i" >> README.md; git commit -qam "wip: step $i"; done
git push -qu origin feat/three
gh pr create --title "feat: three steps" --body "PR 크기 규율 실험" --base main >/dev/null
```

세 가지 머지를 상상하고 결과를 비교하세요 (실제로는 squash로 진행):

```markdown
| 방식 | main의 커밋 | git bisect | revert 난이도 |
|------|-----------|-----------|--------------|
| merge commit | 3 + 병합커밋 | 브랜치 구조 때문에 복잡 | 병합커밋 revert(-m 필요) |
| squash | **1** | 선형 — 각 커밋이 배포 단위 | `git revert <sha>` 하나 |
| rebase merge | 3 | 선형이나 중간 커밋은 미검증 | 3개 revert |
```

```bash
gh pr merge --squash --delete-branch --admin 2>/dev/null || echo "(CI 필수 검사 때문에 머지 불가 — 정상! 게이트가 일하고 있습니다)"
```

✅ 흥미로운 관찰: **필수 상태 검사 `ci`가 존재하지 않아 머지가 막힙니다.** 게이트를 선언했으면 그 게이트를 실제로 제공해야 합니다 — 03(GitHub Actions)에서 이 `ci` 검사를 만듭니다. 지금은 규칙을 완화:

```bash
gh api -X PUT "repos/$REPO/branches/main/protection" \
  -F "required_status_checks=null" -F "enforce_admins=true" \
  -f "required_pull_request_reviews[required_approving_review_count]=0" \
  -F "restrictions=null" >/dev/null
gh pr merge --squash --delete-branch --admin
git checkout -q main && git pull -q
git log --oneline -2      # 세 커밋이 하나로
```

## Step 5. 리뷰 시간 측정 — 리드 타임의 진짜 최대 항 (theory §7)

실제 활동이 있는 저장소에서(회사 저장소 또는 오픈소스) 두 시간을 재보세요:

```bash
TARGET=${TARGET:-kubernetes-sigs/karpenter}   # 예시 — 자기 저장소로 바꿀 것

gh pr list --repo $TARGET --state merged --limit 30 \
  --json number,createdAt,mergedAt,reviews \
  --jq '.[] | select(.reviews|length>0) |
    { n: .number,
      first_review_h: (((.reviews[0].submittedAt|fromdate) - (.createdAt|fromdate)) / 3600 | floor),
      merge_h: (((.mergedAt|fromdate) - (.createdAt|fromdate)) / 3600 | floor) }' \
  | head -15
```

집계:

```bash
gh pr list --repo $TARGET --state merged --limit 50 --json createdAt,mergedAt \
  --jq '[.[] | ((.mergedAt|fromdate) - (.createdAt|fromdate))/3600] | sort |
        {p50: .[(length/2|floor)], p90: .[(length*0.9|floor)], max: .[-1]}'
```

```markdown
# 리드 타임 분해 (기록)
| 구간 | 시간 |
|------|------|
| PR 열기 → 첫 리뷰 | __h  ← 대개 여기가 최대 |
| 첫 리뷰 → 머지 | __h |
| CI 실행 | __분 |
→ CI를 3분 줄이는 것 vs 첫 리뷰를 6시간 줄이는 것: 어느 쪽이 리드 타임을 더 줄이나요?
```

✅ 01의 DORA 지표 중 **변경 리드 타임**이 어디서 새는지 이 표가 말해줍니다. 대개 답은 "사람의 대기"이고, 그래서 개선책도 기술이 아닙니다: 리뷰 SLA, 작은 PR, 리뷰어 로테이션.

## Step 6. 팀 규칙 문서 (산출물)

```markdown
# Git 워크플로 규칙 v1
## 브랜치
- 모델: GitHub flow (근거: 단일 프로덕션 버전, 일 1회 이상 배포 목표)
- 브랜치 수명 목표: < 1일. 초과 시 쪼갤 방법을 논의
- 이름: `feat/`, `fix/`, `chore/` + 이슈번호

## 보호 (main)
- 직접 push 금지 (관리자 포함 — enforce_admins)
- 필수 검사: `ci` (03에서 구현), 최신 base 요구
- 승인 1명 + CODEOWNERS(도메인 소유자)
- force-push/삭제 금지

## 머지
- squash 기본, 제목은 Conventional Commits (`feat(scope): ...`)
- 롤백 수단: `git revert <squash sha>` — 30분 내 가능한지 분기 점검

## 리뷰
- 첫 응답 SLA: 영업시간 4시간
- PR 400줄 초과 시 분할 논의 (리뷰 결함 발견율 급락 구간)
- 미완성 기능은 피처 플래그로 — 브랜치를 길게 끌지 않습니다
```

## 정리

```bash
bash cleanup.sh    # 실험 저장소 삭제 포함
```
