# Lab 01 — 시크릿 감사: 스캔 게이트와 제거 우선순위

"우리 저장소에 시크릿이 있는가"를 도구로 답하고, 발견된 것을 없애기/줄이기/관리하기로 분류합니다.

전제: git, gitleaks(`brew install gitleaks` 또는 릴리스 바이너리), gh.

## Step 1. 유출 재현 — 개발자의 흔한 실수

```bash
mkdir -p ~/ci-lab/secrets && cd ~/ci-lab/secrets
git init -q . && git config user.email l@e.com && git config user.name L

# 흔한 실수 3종 세트 (실제 값 아님 — 형식만 재현)
cat > config.py <<'EOF'
AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
EOF
cat > deploy.sh <<'EOF'
export GITHUB_TOKEN="ghp_000000000000000000000000000000000000"
curl -H "Authorization: Bearer $GITHUB_TOKEN" ...
EOF
cat > .env <<'EOF'
DATABASE_URL=postgres://admin:SuperSecret123@db.internal:5432/prod
EOF
git add -A && git commit -qm "add deploy config"   # ← 이 순간 이력에 박제됨
```

## Step 2. 스캔 — gitleaks는 이력까지 봅니다

```bash
gitleaks git . 2>&1 | tail -15
```

예상: AWS 키·GitHub PAT·접속 문자열 3건 검출(룰 이름·파일·커밋 표시). 이제 "지우면 되겠지"를 시험해봅시다:

```bash
git rm -q config.py && git commit -qm "remove secrets"
gitleaks git . 2>&1 | grep -c "AKIA" || true
```

예상: **여전히 검출** — 최신 커밋에서 지워도 **이력에 남아 있습니다**. ✅ Git 이력의 시크릿은 rewrite(filter-repo)로도 불완전합니다(포크·클론·캐시에 이미 복제) — **커밋된 시크릿의 유일한 해법은 순환**(theory §6). 그래서 방어는 커밋 "전"이어야 합니다.

## Step 3. 커밋 전 차단 — pre-commit + CI 게이트

```bash
# ① 로컬: pre-commit 훅 (커밋 전 차단 — 최선의 지점)
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
gitleaks protect --staged 2>/dev/null || {
  echo "🚨 스테이징에 시크릿 의심 — 커밋 차단"; exit 1; }
EOF
chmod +x .git/hooks/pre-commit

echo 'TOKEN = "ghp_111111111111111111111111111111111111"' > new.py
git add new.py && git commit -qm "test" 2>&1 | tail -1 || echo "→ 차단됨 ✅"
git reset -q new.py && rm new.py

# ② CI: 조직 전체 안전망 (훅은 개인이 끌 수 있으니)
mkdir -p .github/workflows
cat > .github/workflows/secret-scan.yml <<'EOF'
name: secret-scan
on: [push, pull_request]
permissions: { contents: read }
jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }      # 이력 전체 스캔
      - uses: gitleaks/gitleaks-action@v2
        env: { GITHUB_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
EOF
git add -A && git commit -qm "ci: secret scanning gate"
```

✅ 이중 게이트: pre-commit(개인, 최선의 지점 — 이력에 박히기 전) + CI(조직, 안전망). GitHub 자체의 Secret Scanning(퍼블릭 무료, push protection)도 같은 자리의 방어입니다.

## Step 4. 발견된 시크릿의 분류 — 없애기/줄이기/관리하기

Step 1의 3건을 theory §1의 결정 트리에 태웁니다:

```markdown
| 발견 | 없앨 수 있나요? | 처방 |
|------|--------------|------|
| AWS 키 | ✅ OIDC(07)로 | aws-actions/configure-aws-credentials + role — 키 폐기 |
| GitHub PAT | ✅ 대부분 | GITHUB_TOKEN(잡 수명)/GitHub App 토큰으로 — PAT 폐기 |
| DB 접속 문자열 | ⚠️ 없애긴 어려움 | 줄이기: Vault 동적 발급(TTL) / 최소: 스토어 보관+순환 |
★ 3건 중 2건은 "관리"가 아니라 "제거" 대상이었습니다 — 도구 도입 전에 목록부터
```

## Step 5. 시크릿 → 권한 지도 — 사고 나기 전에 만듭니다

```bash
cat > SECRETS-MAP.md <<'EOF'
# 시크릿 대장 (유출 대응의 첫 참조 — theory §6)
| 시크릿 | 보관 | 열리는 것 | 수명 | 순환 절차 | 마지막 순환 |
|--------|------|-----------|------|-----------|-------------|
| (예) datadog-api-key | ASM prod/datadog | 메트릭 전송 | 정적 ⚠️ | 콘솔 재발급→ESO 자동 전파 | 2026-05 |
| (예) db-migrate | Vault database/ | prod DB DDL | 동적 1h ✅ | 불필요 (TTL) | — |
★ "수명: 정적" 행이 곧 리스크 백로그 — 하나씩 동적/OIDC로
EOF
echo "대장 템플릿 생성 — 실조직에서는 이 표의 완성도가 유출 대응 속도"
```

✅ CircleCI 2023 사고 때 "우리가 CircleCI에 뭘 넣어놨더라?"를 못 답한 조직은 **전부**를 순환해야 했습니다 — 대장이 있으면 영향 범위가 목록이 됩니다.

## Step 6. 산출물

```markdown
# 시크릿 위생 체크리스트
- [x] gitleaks: 이력 포함 스캔 — 커밋된 시크릿은 순환만이 해법
- [x] pre-commit(개인) + CI 게이트(조직) 이중 차단
- [x] 발견분을 없애기/줄이기/관리하기로 분류 (관리가 아니라 제거가 다수)
- [x] 시크릿 → 권한 지도 (유출 대응의 첫 참조)
- [ ] lab-02: 그래도 남는 시크릿의 GitOps 배포 3해법
```

## 정리

저장소는 lab-02와 무관 — 유지해도 되고 cleanup.sh가 함께 정리합니다.
