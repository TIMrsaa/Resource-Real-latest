# Lab 01 — 같은 시나리오, 세 가지 모델

동일한 요구를 세 워크플로로 수행하고 **필요한 단계 수와 브랜치 수명**을 비교합니다. 시나리오는 실무의 전형입니다: 기능 하나를 개발하는 도중 프로덕션에 긴급 버그가 발견됩니다.

```bash
mkdir -p ~/ci-lab && cd ~/ci-lab
```

## Step 1. git-flow — 절차의 세계

```bash
rm -rf flow && mkdir flow && cd flow
git init -q && git config user.email l@e.com && git config user.name L
echo "v1" > app.txt && git add -A && git commit -qm "init" && git branch -M main
git tag v1.0
git checkout -q -b develop

# 기능 개발 시작 (수 주간 지속된다고 가정)
git checkout -q -b feature/search develop
echo "search: wip" >> app.txt && git commit -qam "feat: search (wip)"

# 🔥 그 사이 프로덕션 버그! main에서 hotfix
git checkout -q -b hotfix/1.0.1 main
echo "fix: null check" >> app.txt && git commit -qam "fix: null pointer"
git checkout -q main && git merge -q --no-ff hotfix/1.0.1 -m "merge hotfix" && git tag v1.0.1
git checkout -q develop && git merge -q --no-ff hotfix/1.0.1 -m "merge hotfix to develop"  # ★ 잊으면 재발!

# 기능 완성 → develop → release 브랜치 → main
git checkout -q feature/search && echo "search: done" >> app.txt && git commit -qam "feat: search done"
git checkout -q develop && git merge -q --no-ff feature/search -m "merge feature"
git checkout -q -b release/1.1 develop
echo "rc fixes" >> app.txt && git commit -qam "fix: rc"
git checkout -q main && git merge -q --no-ff release/1.1 -m "release 1.1" && git tag v1.1
git checkout -q develop && git merge -q --no-ff release/1.1 -m "backmerge release"   # ★ 또 양쪽

echo "=== git-flow: 브랜치 $(git branch | wc -l)개, 병합 $(git log --oneline --merges | wc -l)회 ==="
git log --oneline --graph --all | head -12
cd ..
```

관찰: hotfix와 release를 **main과 develop 양쪽에** 반영해야 합니다 — 이 backmerge를 빠뜨리는 것이 "고친 버그가 다음 릴리스에서 부활"하는 고전적 사고입니다.

## Step 2. GitHub flow — 단순함

```bash
rm -rf ghflow && mkdir ghflow && cd ghflow
git init -q && git config user.email l@e.com && git config user.name L
echo "v1" > app.txt && git add -A && git commit -qm "init" && git branch -M main

# 기능: 짧은 브랜치
git checkout -q -b feat/search
echo "search: done" >> app.txt && git commit -qam "feat: search"

# 🔥 프로덕션 버그 — main에서 바로
git checkout -q main && git checkout -q -b fix/npe
echo "fix: null check" >> app.txt && git commit -qam "fix: null pointer"
git checkout -q main && git merge -q --squash fix/npe && git commit -qm "fix: null pointer (#2)"
# → 즉시 배포됩니다 (main = 프로덕션)

# 기능 브랜치는 main을 rebase하고 머지
git checkout -q feat/search && git rebase -q main 2>/dev/null || { git checkout --theirs app.txt 2>/dev/null; git add -A; GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; }
git checkout -q main && git merge -q --squash feat/search && git commit -qm "feat: search (#1)"

echo "=== GitHub flow: 병합 지점 2개, develop 없음, backmerge 없음 ==="
git log --oneline | head -5
cd ..
```

✅ **main 하나뿐**이라 hotfix가 "어디에도 반영"될 필요가 없습니다. 배포 = main의 최신 상태.

## Step 3. 트렁크 기반 + 피처 플래그

```bash
rm -rf trunk && mkdir trunk && cd trunk
git init -q && git config user.email l@e.com && git config user.name L
cat > app.py <<'EOF'
import os
def search(q):
    if os.getenv("FF_SEARCH") == "true":
        return f"searching {q}"     # 미완성 — 꺼져 있습니다
    return "search disabled"
EOF
git add -A && git commit -qm "init" && git branch -M main

# 기능을 "미완성인 채로" 매일 트렁크에 (플래그 뒤에서)
echo "# day1: index skeleton" >> app.py && git commit -qam "feat(search): index skeleton [flag off]"
echo "# day2: ranking"       >> app.py && git commit -qam "feat(search): ranking [flag off]"

# 🔥 버그 — 그냥 커밋 하나
echo "# fix: null check" >> app.py && git commit -qam "fix: null pointer"

# 기능 완성 → 코드 변경 없이 플래그만 켜서 출시
echo "# day3: done" >> app.py && git commit -qam "feat(search): complete [flag still off]"
sed -i 's/os.getenv("FF_SEARCH") == "true"/True/' app.py && git commit -qam "feat(search): enable flag"

echo "=== 트렁크: 브랜치 $(git branch | wc -l)개, 병합 0회, 매 커밋이 배포 가능 ==="
git log --oneline | head -6
cd ..
```

✅ **배포와 출시가 분리됐습니다** — 코드는 계속 나갔고(배포), 기능은 마지막에 켜졌습니다(출시). 롤백도 다릅니다: 문제가 생기면 **플래그만 끄면 됩니다**(재배포 없이!).

## Step 4. 비교표 (산출물)

```markdown
| | git-flow | GitHub flow | 트렁크 기반 |
|---|---|---|---|
| 장기 브랜치 | main, develop | main | main |
| hotfix 반영처 | main + develop (누락 위험) | main | (그냥 커밋) |
| 브랜치 수명 | 주~월 | 시간~일 | < 1일 |
| 미완성 코드 위치 | 브랜치 | 브랜치 | **트렁크(플래그 뒤)** |
| 롤백 수단 | 이전 태그 재배포 | revert 커밋 | **플래그 off** (즉시) |
| 요구되는 것 | 절차 준수 | 기본 CI | 강한 CI + 플래그 규율 |
| 적합 | 다중 버전 지원 제품 | 대부분의 웹 서비스 | 고빈도 배포 조직 |
```

## Step 5. 우리 팀의 선택 (판정 질문)

```markdown
1. 동시에 지원해야 할 프로덕션 버전이 2개 이상인가요? → 예: git-flow류 필요
2. 배포가 하루 1회 이상인가요? → 예: 트렁크 기반 검토
3. 미완성 기능을 안전하게 끌 수 있는가(플래그)? → 아니오면 먼저 그것부터
4. CI가 10분 이내이고 신뢰할 수 있는가요? → 아니오면 브랜치 전략을 바꿔도 소용없습니다
→ 우리의 답: ____________ (근거와 함께)
```

## 정리

```bash
cd ~ && rm -rf ~/ci-lab/{flow,ghflow,trunk}
```
