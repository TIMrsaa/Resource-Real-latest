# Lab 02 — 배포, 버전 관리, 공급망 안전

액션을 버전 태그로 배포하고, 소비자가 안전하게 쓸 수 있게 만듭니다. 03에서 소비자로 배운 공급망 규율을 이제 생산자로서 책임집니다.

전제: lab-01의 액션 저장소(~/ci-lab/action).

## Step 1. 버전 태그 — semver + 이동 태그

```bash
cd ~/ci-lab/action
git tag v1.0.0
git tag -f v1        # ★ 이동 태그 (major) — 소비자가 @v1로 자동 패치 수신
git push origin v1.0.0
git push -f origin v1
echo "릴리스 태그 확인:"
git tag
```

세 가지 참조 방법과 소비자 관점(theory §5):

```markdown
| 소비자가 쓰는 법 | 받는 것 | 안전성 |
|------------------|---------|--------|
| uses: me/action@v1 | v1의 최신(자동 패치) | 편함, 이동 태그 신뢰 |
| uses: me/action@v1.0.0 | 그 릴리스 고정 | semver 고정 |
| uses: me/action@<SHA> | 그 커밋 고정(불변) | ★ 가장 안전 (03의 규율) |
```

## Step 2. 릴리스와 마켓플레이스

```bash
gh release create v1.0.0 --title "Digest Enforcer v1.0.0" \
  --notes "매니페스트의 이미지가 다이제스트(@sha256)를 쓰는지 검증. 04의 불변성 규율을 CI 게이트로."
echo "마켓플레이스 배포: 릴리스 페이지에서 'Publish this Action to the GitHub Marketplace'"
echo "  → action.yml의 name/description/branding이 목록에 표시"
```

## Step 3. 생산자의 공급망 책임 — dist 재현성

소비자는 dist/index.js(번들)를 신뢰해야 합니다 — 그것이 src에서 재현 가능함을 보증합니다:

```bash
cat > .github/workflows/verify-dist.yml <<'EOF'
name: verify-dist
on: [push, pull_request]
permissions: { contents: read }
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npx ncc build src/index.js -o dist
      - name: dist가 src에서 재현되는가 (커밋된 것과 일치?)
        run: |
          if [ -n "$(git status --porcelain dist/)" ]; then
            echo "🚨 dist가 src와 불일치 — 번들을 다시 커밋하세요"
            git diff dist/ | head
            exit 1
          fi
          echo "✅ dist가 src에서 재현됨 (소비자가 신뢰 가능)"
EOF
git add -A && git commit -qm "ci: verify dist reproducibility" && git push -q
```

✅ **dist 재현성 검증**이 생산자의 공급망 책임입니다 — 소비자가 "커밋된 dist가 정말 이 src에서 나온 것"임을 신뢰할 수 있게. dist가 몰래 조작되면(악성 코드 주입) 이 검증이 잡습니다.

## Step 4. 최소 권한 문서화

내 액션이 요구하는 권한을 명시(소비자가 최소 권한을 줄 수 있게):

```bash
cat > README.md <<'EOF'
# Digest Enforcer

매니페스트의 이미지 참조가 다이제스트(@sha256)를 쓰는지 검증합니다 (불변성 강제).

## 사용법
```yaml
permissions:
  contents: read              # ★ 이 액션이 요구하는 유일한 권한
steps:
  - uses: actions/checkout@v4
  - uses: your-org/digest-enforcer@v1    # 또는 @<SHA>로 고정 (권장)
    with:
      path: manifests
      fail-on-tag: 'true'
```

## 보안
- 요구 권한: `contents: read` 만
- 네트워크 접근 없음 (파일만 읽음)
- SHA 고정 권장: `@<커밋SHA>` 로 불변 참조
- dist는 src에서 재현 검증됨 (verify-dist 워크플로)
EOF
git add -A && git commit -qm "docs: security and usage" && git push -q
```

✅ 03에서 소비자로 "이 액션이 안전한가"를 물었다면, 생산자로서 그 질문에 **문서로 답**합니다: 요구 권한, 네트워크 접근, 검증 방법.

## Step 5. 의존성 취약점 — dist도 코드입니다

```bash
# node_modules가 dist에 번들되므로, 그 취약점도 배포됩니다
npm audit 2>&1 | tail -10 || echo "취약점 없음"

cat <<'EOF'
# 액션의 공급망 관리
- Dependabot으로 의존성 갱신 PR (dist 재빌드 필요)
- npm audit을 CI 게이트로
- 번들된 dist = 소비자에게 배포되는 코드 → 그 취약점도 소비자의 것
- 최소 의존성 (적은 의존성 = 적은 공급망 위험)
EOF
```

## Step 6. 좋은 액션 vs 나쁜 액션 (03의 반대편)

```markdown
# 소비자를 위한 생산자 체크리스트 (내 액션이 안전하다는 보증)
## 투명성
- [x] 소스 공개, dist가 src에서 재현 검증 (verify-dist)
- [x] 무엇을 하는지 README에 명확

## 최소 권한
- [x] 요구 permissions 문서화 (contents: read만)
- [x] 불필요한 네트워크·시크릿 접근 없음

## 입력 안전
- [x] @actions/core로 입력 처리 (인젝션 방어 — 03)
- [x] 입력 검증 (경로 탈출 등)

## 버전
- [x] semver + 이동 태그, SHA 고정 가능
- [x] 보안 감사된 릴리스만 태그

## 의존성
- [x] npm audit, Dependabot
- [x] 최소 의존성
→ 이 체크리스트가 곧 "나쁜 액션 알아보기"(03 소비자 관점)의 반대편
```

## Step 7. 27로의 연결 — 기여 사다리

```markdown
# 액션 개발 → actions/runner 기여 (27의 CI/CD판)
- 액션을 만들며 액션 실행 모델을 생산자로 이해
- @actions/toolkit에 기여 (버그·기능)
- actions/runner(액션이 실행되는 러너) 코드 이해·기여
- 27(security)과 연결: 공급망 안전이 곧 보안 기여
→ 소비자 → 생산자 → 기여자 (eks 27의 사다리와 동형)
```

## Step 8. 고급 진도

```markdown
18 → 커스텀 액션: 소비자에서 생산자로                     [ ]
→ 19(BuildKit 심층): 04의 빌드를 내부까지, ko/kaniko/buildpacks
→ 20(모노레포 CI): 06의 동적 매트릭스 + affected 빌드
```

## 정리

```bash
bash cleanup.sh
```
