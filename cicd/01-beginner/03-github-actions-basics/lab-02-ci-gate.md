# Lab 02 — `ci` 게이트 완성: 02가 남긴 빈칸을 채웁니다

02에서 브랜치 보호에 `ci` 필수 검사를 선언했지만 아무도 그것을 제공하지 않아 머지가 막혔습니다. 이제 만듭니다 — 01의 파이프라인 3원칙(빠른 피드백·병렬화·신뢰)을 YAML로.

## Step 1. 검증할 앱

```bash
cd ~/ci-lab/gha
rm -f .github/workflows/{mystery,jobs,inject,context}.yml

mkdir -p app tests
cat > app/calc.py <<'EOF'
def add(a, b):
    return a + b

def divide(a, b):
    if b == 0:
        raise ValueError("division by zero")
    return a / b
EOF
cat > tests/test_calc.py <<'EOF'
import pytest
from app.calc import add, divide

def test_add():
    assert add(2, 3) == 5

def test_divide():
    assert divide(6, 3) == 2

def test_divide_by_zero():
    with pytest.raises(ValueError):
        divide(1, 0)
EOF
cat > requirements-dev.txt <<'EOF'
pytest==8.3.4
ruff==0.9.2
EOF
touch app/__init__.py
```

## Step 2. `ci` 워크플로 — 원칙을 코드로

```bash
cat > .github/workflows/ci.yml <<'EOF'
name: ci                       # ★ 이 이름이 브랜치 보호의 필수 검사와 매칭됩니다

on:
  pull_request:                # 포크 PR도 안전하게 (시크릿 없음 — theory §3)
  push:
    branches: [main]

concurrency:                   # 새 push가 오면 이전 실행 취소 (러너 절약)
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read               # 최소 권한

jobs:
  # ── 원칙 ①: 싸고 자주 실패하는 것을 먼저, 그리고 병렬로 ──
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip                       # 의존성 캐시 (러너는 매번 새 VM!)
      - run: pip install -r requirements-dev.txt
      - run: ruff check app tests
      - run: ruff format --check app tests

  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false                     # 한 버전 실패해도 나머지 결과를 봅니다
      matrix:
        python: ["3.11", "3.12", "3.13"]   # 매트릭스 — 잡이 3개로 늘어납니다
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python }}
          cache: pip
      - run: pip install -r requirements-dev.txt
      - run: pytest -q tests/

  # ── 원칙 ②: 게이트 하나로 수렴 (브랜치 보호가 참조할 단일 검사) ──
  ci:
    if: always()
    needs: [lint, test]
    runs-on: ubuntu-latest
    steps:
      - name: 모든 선행 잡이 성공했는가
        run: |
          echo "lint=${{ needs.lint.result }} test=${{ needs.test.result }}"
          [ "${{ needs.lint.result }}" = "success" ] && [ "${{ needs.test.result }}" = "success" ]
EOF
git add -A && git commit -qm "ci: add ci workflow" && git push -q
```

✅ 마지막 `ci` 잡이 핵심 설계입니다: **매트릭스가 늘어나도 브랜치 보호는 `ci` 하나만 참조하면 됩니다.** 매트릭스 잡 이름(`test (3.11)`…)을 필수 검사에 일일이 등록하는 안티패턴을 피합니다.

## Step 3. 게이트 작동 확인 — 실패하는 PR

```bash
git checkout -q -b feat/break-it
cat >> app/calc.py <<'EOF'

def multiply(a,b):
    return a*b     # ruff format 위반: 공백 규칙
EOF
git commit -qam "feat: multiply (스타일 위반)" && git push -qu origin feat/break-it
gh pr create --title "feat: multiply" --body "게이트 실험" --base main >/dev/null

sleep 60
gh pr checks 2>/dev/null || gh run list --limit 3
```

예상: `lint` 실패 → `ci` 실패. **10초 만에 피드백**(test 3개는 병렬로 돌지만 lint가 먼저 끝납니다).

수정:

```bash
sed -i 's/def multiply(a,b):/def multiply(a, b):/; s/    return a\*b.*/    return a * b/' app/calc.py
git commit -qam "style: fix formatting" && git push -q
sleep 70; gh pr checks 2>/dev/null | head -6
```

## Step 4. 브랜치 보호에 `ci` 연결 — 02의 완성

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api -X PUT "repos/$REPO/branches/main/protection" \
  -H "Accept: application/vnd.github+json" \
  -f "required_status_checks[strict]=true" \
  -F "required_status_checks[contexts][]=ci" \
  -F "enforce_admins=true" \
  -f "required_pull_request_reviews[required_approving_review_count]=0" \
  -F "restrictions=null" -F "allow_force_pushes=false" >/dev/null

# 이제 게이트가 실제로 막습니다
git checkout -q main
echo "직접 수정" >> README.md && git commit -qam "직접 push 시도"
git push 2>&1 | tail -2
git reset -q --hard origin/main
```

예상: `protected branch hook declined` — ✅ **02의 선언 + 03의 구현 = 작동하는 게이트.**

```bash
gh pr merge --squash --delete-branch   # CI 통과했으므로 머지됩니다
```

## Step 5. 캐시의 효과 측정 (01의 "빠른 피드백")

```bash
# 최근 두 번의 test 잡 소요 시간 비교 (첫 실행: 캐시 미스, 이후: 히트)
gh run list --workflow=ci --limit 5 --json databaseId,createdAt,updatedAt,conclusion \
  --jq '.[] | {id: .databaseId, sec: (((.updatedAt|fromdate) - (.createdAt|fromdate)))}'
```

`cache: pip`이 없을 때와 있을 때의 차이를 재보려면 잠시 지워보세요 — 의존성이 무거운 프로젝트(node_modules, Go 모듈)일수록 극적입니다. 04(빌드 캐시)에서 이 주제를 본격적으로 다룹니다.

## Step 6. 산출물 — 우리 팀의 CI 스켈레톤

```markdown
# ci.yml 설계 결정
- 트리거: pull_request(포크 안전) + push:main. `pull_request_target` 사용 금지
- concurrency: 같은 ref의 이전 실행 취소 (비용·대기 절감)
- permissions: contents:read 기본, 필요한 잡만 확장 (07의 id-token 등)
- 잡 구조: [lint ‖ test(matrix)] → ci(수렴 잡)
  → 브랜치 보호는 `ci` 하나만 필수 검사로 등록 (매트릭스 확장에 안전)
- 캐시: setup-* 액션의 cache 옵션부터. 부족하면 actions/cache (04)
- 목표: 실패 피드백 < 1분, 전체 < 10분 (01 원칙)
```

## 정리

```bash
bash cleanup.sh
```
