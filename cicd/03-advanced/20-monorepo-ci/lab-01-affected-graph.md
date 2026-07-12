# Lab 01 — path filter의 맹점을 밟고, 그래프 affected로 건너기

공유 라이브러리 하나와 소비자 둘로 최소 모노레포를 만들고, "침묵의 회귀"를 직접 재현한 뒤 그래프로 잡습니다.

전제: node 20+, npm.

## Step 1. 최소 모노레포 — lib 하나, 소비자 둘

```bash
mkdir -p ~/ci-lab/mono/{libs/shared,services/api,services/web} && cd ~/ci-lab/mono
git init -q . && git config user.email l@e.com && git config user.name L

cat > package.json <<'EOF'
{ "name": "mono", "private": true,
  "workspaces": ["libs/*", "services/*"],
  "packageManager": "npm@10.0.0" }
EOF

cat > libs/shared/package.json <<'EOF'
{ "name": "@mono/shared", "version": "1.0.0", "main": "index.js",
  "scripts": { "test": "node test.js" } }
EOF
cat > libs/shared/index.js <<'EOF'
exports.greet = (who) => `Hello, ${who}`;
EOF
cat > libs/shared/test.js <<'EOF'
const { greet } = require('./index');
if (greet('x') !== 'Hello, x') { console.error('shared FAIL'); process.exit(1); }
console.log('shared OK');
EOF

for SVC in api web; do
cat > services/$SVC/package.json <<EOF
{ "name": "@mono/$SVC", "version": "1.0.0",
  "dependencies": { "@mono/shared": "*" },
  "scripts": { "test": "node test.js" } }
EOF
cat > services/$SVC/test.js <<'EOF'
const { greet } = require('@mono/shared');
if (!greet('svc').startsWith('Hello')) { console.error('FAIL'); process.exit(1); }
console.log('OK');
EOF
done

npm install >/dev/null 2>&1
git add -A && git commit -qm "monorepo baseline"
```

## Step 2. 침묵의 회귀 재현 — path filter는 lib 변경을 못 봅니다

path filter를 흉내내는 셸(폴더 매핑)로 "무엇을 테스트할지" 정해봅시다:

```bash
# shared의 동작을 바꿔서 소비자를 깨뜨립니다 (반환 형식 변경)
sed -i "s/Hello, \${who}/hi \${who}/" libs/shared/index.js
git add -A && git commit -qm "feat(shared): change greeting format"

# path filter 방식: 바뀐 폴더만 테스트
CHANGED=$(git diff --name-only HEAD~1 | cut -d/ -f1-2 | sort -u)
echo "변경 폴더: $CHANGED"
for DIR in $CHANGED; do
  PKG=$(node -p "require('./$DIR/package.json').name" 2>/dev/null) || continue
  npm test -w $PKG 2>&1 | tail -1
done
```

예상: `libs/shared`만 테스트되고 — shared 자체 테스트는 통과합니다(greet가 문자열을 반환하긴 하니까 shared OK... 는 사실 shared 테스트가 'Hello, x'를 검사하므로 **shared FAIL**이 뜬다면 그것대로 좋습니다). 중요한 것은 **api·web 테스트는 아예 실행되지 않았다**는 점입니다:

```bash
npm test -w @mono/api 2>&1 | tail -1   # 수동으로 돌려보면...
```

예상: api 테스트도 이 변경의 영향권인데 path filter는 그것을 몰랐습니다. ✅ **필터 목록은 의존성 그래프의 수동 사본**이고, 사본은 낡습니다(theory §2). 이것이 "머지됐는데 옆 팀 서비스가 깨진" 침묵의 회귀입니다.

```bash
git revert -q --no-edit HEAD   # 원상 복구
```

## Step 3. Turborepo — 그래프를 자동 추출

```bash
npm install -D turbo >/dev/null 2>&1
cat > turbo.json <<'EOF'
{
  "$schema": "https://turborepo.com/schema.json",
  "tasks": {
    "test": { "dependsOn": ["^test"], "inputs": ["**/*.js", "package.json"] }
  }
}
EOF
git add -A && git commit -qm "chore: turborepo"

# 그래프 확인 — 도구가 dependencies에서 추출한 의존 관계
npx turbo ls 2>/dev/null
npx turbo run test --dry=json 2>/dev/null | head -30
```

예상: shared → api, shared → web 의존이 그래프로 보입니다. ✅ 사람이 목록을 관리하지 않습니다 — package.json이 곧 그래프.

## Step 4. affected — 같은 변경, 이번엔 잡힙니다

```bash
# Step 2와 같은 변경을 다시
sed -i "s/Hello, \${who}/hi \${who}/" libs/shared/index.js
git add -A && git commit -qm "feat(shared): change greeting format (take 2)"

# main 대비 affected만 테스트
npx turbo run test --filter='...[HEAD~1]' 2>&1 | grep -E "@mono|FAIL|OK|Tasks:" | head -10
```

예상: **shared·api·web 셋 다** 실행되고, api/web 테스트가 실패합니다(형식이 바뀌었으니). ✅ affected = 변경 프로젝트 + **역방향 전이 의존자**(theory §3) — path filter가 놓친 회귀를 그래프가 잡았습니다.

```bash
git revert -q --no-edit HEAD
```

## Step 5. 캐시 — "같은 입력 = 같은 출력"을 눈으로

```bash
npx turbo run test 2>&1 | grep -E "cached|Tasks:"       # 1차: 전부 실행
npx turbo run test 2>&1 | grep -E "cached|Tasks:|FULL"  # 2차: 아무것도 안 바뀜
```

예상: 2차는 `cached, 3 total` + **FULL TURBO** — 실행 0건, 저장된 출력 재생. 이제 하나만 바꾸면:

```bash
touch services/api/test.js && echo "// comment" >> services/api/test.js
npx turbo run test 2>&1 | grep -E "cached|Tasks:"
```

예상: api만 재실행(1 total... 정확히는 api 1건 실행 + 2건 cached). ✅ 태스크 해시 = 입력 파일들의 해시 — **19의 BuildKit 캐시와 같은 아이디어, 다른 층**(theory §3). 원격 캐시를 붙이면 이 재사용이 CI·팀 전체로 확장됩니다.

## Step 6. 그래프의 한계 확인 — 루트 설정 변경

```bash
echo '{}' > .some-global-config.json
git add -A && git commit -qm "chore: global config"
npx turbo run test --filter='...[HEAD~1]' --dry=json 2>/dev/null | grep -c '"@mono' || echo "0"
```

예상: turbo.json의 inputs에 없는 파일이라 affected 0건 — 하지만 이 파일이 실제로 빌드에 영향을 준다면? **그래프는 선언된 입력만 압니다**(theory §5). 전역 설정은 `globalDependencies`로 선언하거나, 바뀌면 전체 실행을 감수해야 합니다. 캐시·affected의 신뢰도는 입력 선언의 정직함에 비례합니다(Bazel이 이것을 샌드박스로 강제).

## 정리

lab-02에서 이 저장소를 GHA에 올려 동적 매트릭스와 required check 게이트를 만듭니다. 저장소 유지.
