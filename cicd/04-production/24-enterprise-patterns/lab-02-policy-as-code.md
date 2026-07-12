# Lab 02 — Policy as Code: 파이프라인 정의 자체를 검사하는 게이트

03~21에서 배운 규율(permissions 명시, SHA 고정, 인젝션 조합 금지)을 rego 정책으로 코드화하고, 워크플로 YAML을 머지 전에 검사합니다.

전제: lab-01의 저장소, conftest(`brew install conftest` 또는 릴리스 바이너리).

## Step 1. 정책 작성 — 규율을 rego로

```bash
cd ~/ci-lab/enterprise && mkdir -p policy
cat > policy/workflow.rego <<'EOF'
package main

# ── 정책 1: permissions 미명시 금지 (03의 최소 권한) ──
deny contains msg if {
	not input.permissions
	msg := "워크플로 최상위에 permissions 명시 필요 (03: 기본 토큰 권한 축소)"
}

# ── 정책 2: 서드파티 액션은 SHA 고정 (03·18·21의 공급망) ──
deny contains msg if {
	some job in input.jobs
	some step in job.steps
	uses := step.uses
	not startswith(uses, "./")                    # 로컬 액션 제외
	not startswith(uses, "actions/")              # 1st-party는 (예시로) 태그 허용
	not regex.match(`@[0-9a-f]{40}$`, uses)       # 40자 SHA가 아니면
	msg := sprintf("서드파티 액션은 커밋 SHA로 고정: %s (tj-actions 사고 — 21)", [uses])
}

# ── 정책 3: pull_request_target + checkout 조합 경고 (03의 인젝션) ──
deny contains msg if {
	input.on.pull_request_target
	some job in input.jobs
	some step in job.steps
	contains(step.uses, "actions/checkout")
	msg := "pull_request_target에서 checkout — 03의 인젝션 패턴, 설계 리뷰 필요"
}

# ── 정책 4: 하드코딩된 시크릿 의심 문자열 (22) ──
deny contains msg if {
	some job in input.jobs
	some step in job.steps
	regex.match(`(AKIA[A-Z0-9]{16}|ghp_[A-Za-z0-9]{36})`, step.run)
	msg := "run 스텝에 자격증명 의심 문자열 (22: 시크릿은 스토어/OIDC로)"
}
EOF
```

## Step 2. 위반 워크플로로 검증 — 정책이 실제로 잡는가

```bash
mkdir -p test-workflows
cat > test-workflows/bad.yml <<'EOF'
name: bad-example
on: { pull_request_target: {} }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: some-vendor/cool-action@v2
      - run: export AWS_KEY=AKIAIOSFODNN7EXAMPLE
EOF

conftest test test-workflows/bad.yml -p policy/ 2>&1 | tail -8
```

예상: **4건 deny** — permissions 없음, 서드파티 태그 참조, pull_request_target+checkout, 자격증명 문자열. ✅ 문서로 존재하던 규율이 실행 가능한 검사가 됐습니다. 부정 테스트(정책이 잡는지)를 정책 자체의 테스트로 유지하세요 — 21의 "무엇이 통과 못 하는가" 리뷰와 같은 원리.

## Step 3. 통과 사례 — 골든 패스는 정책을 공짜로 지납니다

```bash
cat > test-workflows/good.yml <<'EOF'
name: good-example
on: [pull_request]
permissions: { contents: read }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: some-vendor/cool-action@8f4b7f84864484a7bf31766abe9204da3cbe65b3
      - run: echo "secrets come from OIDC, not hardcoded"
EOF
conftest test test-workflows/good.yml -p policy/ 2>&1 | tail -2
```

예상: 통과. ✅ 플랫폼 팀의 reusable workflow(06)가 처음부터 이 형태라면 — 팀들은 정책을 의식하지 않고도 통과합니다(**골든 패스에 보안이 내장**, theory §4).

## Step 4. 게이트로 배치 — 워크플로를 검사하는 워크플로

```bash
cat > .github/workflows/policy-check.yml <<'EOF'
name: policy-check
on:
  pull_request:
    paths: ['.github/workflows/**']    # 파이프라인 정의가 바뀔 때 (독립 영역이라 path filter 안전 — 20)
permissions: { contents: read }
jobs:
  conftest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: conftest 설치
        run: |
          curl -sL https://github.com/open-policy-agent/conftest/releases/latest/download/conftest_Linux_x86_64.tar.gz \
            | tar xz conftest && sudo mv conftest /usr/local/bin/
      - name: 워크플로 정책 검사
        run: conftest test .github/workflows/*.yml -p policy/
EOF
git add -A && git commit -qm "ci: policy as code gate" && git push -q
```

검증 — 위반 워크플로를 PR로:

```bash
git checkout -qb add-bad-workflow
cp test-workflows/bad.yml .github/workflows/bad.yml
git add -A && git commit -qm "add workflow" && git push -qu origin add-bad-workflow
gh pr create --title "TICKET-1: new workflow" --body "TICKET-1" >/dev/null
sleep 60
gh pr checks 2>/dev/null | grep -E "policy|conftest" || gh run list --limit 2
gh pr close add-bad-workflow -d 2>/dev/null; git checkout -q main
```

예상: policy-check 실패 — **위반 파이프라인이 조직에 들어오지 못합니다**. ✅ 실조직에서는 이것을 required workflow(조직 수준)로 걸어 전 저장소에 적용합니다 — 03~21의 규율이 전사 게이트가 되는 순간.

## Step 5. 정책의 거버넌스 — 정책도 코드입니다

```markdown
# 정책 운영 원칙
- 정책 저장소는 별도 + CODEOWNERS = 보안/플랫폼 팀 (정책 변경도 리뷰를 거침)
- 새 정책은 warn(경고)으로 시작 → 위반 목록 소진 → deny 승격 (21의 audit→enforce와 동일)
- 각 정책에 "왜"와 모듈 참조를 주석으로 — 규칙의 이유가 없으면 우회가 정당화됩니다
- 예외는 정책 코드에 명시(허용 목록 + 사유) — 채팅 승인은 감사에 안 남습니다
- 분기 리뷰: 위반률(23)과 예외 목록 — 위반이 많은 정책은 규칙이 아니라 현실이 문제일 수도
```

## Step 6. 산출물 — 거버넌스 배치도

```markdown
# 우리 조직의 거버넌스 스택 (이 모듈의 종합)
강제(좁게)   org 룰셋(02 표준) / 허용 액션(03) / required workflow: policy-check(24) + secret-scan(22)
             OIDC subject 표준(07) / 서명·admission(21) / prod 승인+SoD(24)
유인(넓게)   reusable workflow 골든 패스(06) — 캐시(19)·서명(21)·SBOM 내장
측정(전체)   DORA·파이프라인 SLO(23) / 골든 패스 채택률 / 정책 위반률 / break-glass 횟수
```

## 정리

```bash
bash cleanup.sh
```
