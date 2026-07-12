# Lab 01 — 같은 로직, 세 가지 재사용 수단

같은 CI 로직을 composite action과 reusable workflow로 각각 구현하고 — **무엇이 가능하고 무엇이 막히는지**를 실패로 배웁니다.

## Step 1. 공용 저장소 (조직의 `.github` 역할)

```bash
mkdir -p ~/ci-lab/shared/{.github/workflows,setup-python-app} && cd ~/ci-lab/shared
git init -q && git config user.email l@e.com && git config user.name L
```

### composite action — 스텝 묶음

```bash
cat > setup-python-app/action.yml <<'EOF'
name: Setup Python App
description: 파이썬 설정 + 의존성 설치 (여러 워크플로에서 반복되는 스텝들)
inputs:
  python-version:
    description: Python 버전
    default: "3.12"
  requirements:
    description: 요구사항 파일
    default: requirements-dev.txt
runs:
  using: composite            # ★ JS도 Docker도 아닌 "스텝 묶음"
  steps:
    - uses: actions/setup-python@v5
      with:
        python-version: ${{ inputs.python-version }}
        cache: pip
    - name: 의존성 설치
      shell: bash             # ★ composite에서는 shell 명시 필수
      run: pip install -r ${{ inputs.requirements }}
    - name: 버전 확인
      shell: bash
      run: python --version
EOF
```

### reusable workflow — 잡 통째로

```bash
cat > .github/workflows/reusable-ci.yml <<'EOF'
name: reusable-ci
on:
  workflow_call:                        # ★ 이 트리거가 "호출당할 수 있음"을 선언
    inputs:
      python-version:
        type: string
        default: "3.12"
      run-integration:
        type: boolean
        default: false
    outputs:
      tested-version:
        value: ${{ jobs.test.outputs.version }}
    # secrets: 은 필요할 때만 명시 선언 (inherit 금지 — theory §2)

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest              # ★ composite은 못 하는 것: 러너 선택
    outputs:
      version: ${{ steps.v.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - uses: ./setup-python-app        # 같은 저장소의 composite을 잡 안에서 사용
        with:
          python-version: ${{ inputs.python-version }}
      - id: v
        run: echo "version=$(python -V | cut -d' ' -f2)" >> "$GITHUB_OUTPUT"
      - run: pytest -q -m "not quarantine" tests/ || echo "(테스트 없음 — 데모)"

  integration:
    if: inputs.run-integration          # ★ composite은 못 하는 것: 조건부 잡
    runs-on: ubuntu-latest
    services:                           # ★ composite은 못 하는 것: service container
      postgres:
        image: postgres:17
        env: { POSTGRES_PASSWORD: test }
        options: --health-cmd pg_isready --health-interval 5s --health-retries 10
        ports: ["5432:5432"]
    steps:
      - uses: actions/checkout@v4
      - run: echo "통합 테스트 (DB 준비됨)"
EOF

cat > requirements-dev.txt <<'EOF'
pytest==8.3.4
EOF
mkdir -p tests && echo "def test_ok(): assert True" > tests/test_smoke.py

git add -A && git commit -qm "shared: composite action + reusable workflow"
gh repo create cicd-lab-shared --public --source=. --push >/dev/null
SHARED=$(gh repo view --json nameWithOwner -q .nameWithOwner)
SHA=$(git rev-parse HEAD)
echo "공용 저장소: $SHARED @ $SHA"
```

## Step 2. 소비자 저장소 — 두 방식으로 호출

```bash
mkdir -p ~/ci-lab/consumer/.github/workflows && cd ~/ci-lab/consumer
git init -q && git config user.email l@e.com && git config user.name L
cp -r ~/ci-lab/shared/tests . && cp ~/ci-lab/shared/requirements-dev.txt .

cat > .github/workflows/ci.yml <<EOF
name: ci
on: [push, workflow_dispatch]
permissions:
  contents: read

jobs:
  # ── 방식 A: reusable workflow — 잡 전체를 위임
  standard-ci:
    uses: $SHARED/.github/workflows/reusable-ci.yml@$SHA   # ★ SHA 고정
    with:
      python-version: "3.13"
      run-integration: true
    # secrets: 필요한 것만 명시 (inherit 금지)

  # ── 방식 B: composite action — 내 잡 안에서 스텝만 재사용
  custom-job:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: $SHARED/setup-python-app@$SHA                 # ★ 스텝 자리
        with:
          python-version: "3.11"
      - run: echo "이 잡은 내가 통제한다"

  # ── 결과 수렴 (03의 게이트 패턴)
  ci:
    if: always()
    needs: [standard-ci, custom-job]
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "reusable outputs: \${{ needs.standard-ci.outputs.tested-version }}"
          [ "\${{ needs.standard-ci.result }}" = "success" ] && [ "\${{ needs.custom-job.result }}" = "success" ]
EOF

git add -A && git commit -qm "ci: use shared workflows"
gh repo create cicd-lab-consumer --public --source=. --push >/dev/null
sleep 90
gh run list --limit 1
gh run view --log 2>/dev/null | grep -E "reusable outputs|이 잡은|Python 3" | head -4
```

✅ 관찰할 것 세 가지:

1. `standard-ci`는 **잡이 두 개**(test, integration)로 확장됐습니다 — reusable은 잡을 만듭니다
2. `custom-job`은 내 잡 안에서 스텝만 빌려 썼습니다 — composite은 스텝을 만듭니다
3. reusable의 outputs가 `needs.standard-ci.outputs`로 넘어왔습니다

## Step 3. 제약을 실패로 확인 — composite에 `runs-on`을 넣으면?

```bash
cd ~/ci-lab/shared
cp setup-python-app/action.yml /tmp/action.bak
cat > setup-python-app/action.yml <<'EOF'
name: broken
description: composite에 잡 속성을 넣으면?
runs:
  using: composite
  runs-on: ubuntu-latest      # 🚨 잡의 속성 — 여기 올 수 없습니다
  steps:
    - shell: bash
      run: echo hi
EOF
git commit -qam "test: broken composite" >/dev/null && git push -q
cd ~/ci-lab/consumer && gh workflow run ci.yml && sleep 40
gh run view --log-failed 2>/dev/null | grep -i "unexpected\|invalid" | head -2 || echo "(액션 파싱 에러 확인)"

cd ~/ci-lab/shared && cp /tmp/action.bak setup-python-app/action.yml
git commit -qam "revert: broken composite" >/dev/null && git push -q
```

✅ **`runs-on`, `services`, `strategy`, `permissions`는 잡의 속성**입니다 — composite action(스텝 묶음)에 넣을 수 없습니다. 이 경계를 알면 "왜 안 되지"가 사라집니다.

## Step 4. 시크릿 폭발 반경 실험 (개념 확인)

```bash
cd ~/ci-lab/consumer
gh secret set PROD_TOKEN --body "super-secret-prod"
gh secret set DEV_TOKEN --body "dev-only"

cat > .github/workflows/secrets-demo.yml <<EOF
name: secrets-demo
on: workflow_dispatch
jobs:
  # ❌ 위험: 모든 시크릿을 넘깁니다
  inherit-all:
    uses: $SHARED/.github/workflows/reusable-ci.yml@$SHA
    secrets: inherit

  # ✅ 안전: 필요한 것만 (이 예시에선 아무것도 필요 없습니다)
  explicit:
    uses: $SHARED/.github/workflows/reusable-ci.yml@$SHA
EOF
git add -A && git commit -qm "demo: secret scope" && git push -q
```

생각해볼 것: `inherit-all`은 공용 저장소의 워크플로에 **PROD_TOKEN까지** 넘깁니다. 그 저장소에 커밋 권한이 있는 사람(또는 그것을 탈취한 사람)은 시크릿을 유출할 수 있습니다.

```markdown
# 시크릿 전달 규칙
- 같은 저장소의 reusable → inherit 허용
- 다른 저장소(조직 공용) → **명시적 전달만**, 필요한 것만
- 프로덕션 시크릿은 아예 environment로 격리 (lab-02)
```

## Step 5. 산출물 — 선택 기준표

```markdown
# 재사용 수단 결정표 (우리 조직)
| 상황 | 선택 | 이유 |
|------|------|------|
| "setup + 캐시 + 설치" 3스텝 반복 | composite action | 스텝 묶음, 잡 자유도 유지 |
| "표준 CI 잡 세트(러너·서비스·매트릭스 포함)" | reusable workflow | 잡 수준 표준화 |
| "새 저장소 시작점" | starter workflow | 이후 각자 진화 |
| 버전 참조 | **SHA 고정** + Dependabot | 태그는 움직입니다 |
| 시크릿 | 외부 호출엔 명시 전달, 프로덕션은 environment |
```

## 정리

두 저장소는 lab-02에서 계속 사용.
