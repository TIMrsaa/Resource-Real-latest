# Lab 01 — JavaScript 액션 개발: 입출력, 툴킷, 테스트

실제로 쓸모 있는 액션(이미지 다이제스트 검증 — 04의 규율을 강제)을 만들며, 03의 소비 지식이 생산으로 완성되는 것을 봅니다.

## Step 1. 프로젝트 구조

```bash
mkdir -p ~/ci-lab/action/{src,__tests__,dist} && cd ~/ci-lab/action
git init -q && git config user.email l@e.com && git config user.name L
npm init -y >/dev/null
npm install @actions/core @actions/github >/dev/null 2>&1
npm install -D @vercel/ncc jest >/dev/null 2>&1
```

## Step 2. action.yml — 계약

우리 액션: "매니페스트가 태그가 아니라 다이제스트를 쓰는지 검증"(04의 규율을 CI 게이트로):

```bash
cat > action.yml <<'EOF'
name: 'Digest Enforcer'
description: '매니페스트의 이미지 참조가 다이제스트(@sha256)인지 검증 (04의 불변성 강제)'
inputs:
  path:
    description: '검사할 매니페스트 파일/디렉터리'
    required: true
    default: '.'
  fail-on-tag:
    description: '태그 발견 시 실패할지'
    required: false
    default: 'true'
outputs:
  violations:
    description: '태그로 참조된 이미지 수'
runs:
  using: 'node20'
  main: 'dist/index.js'
branding:
  icon: 'lock'
  color: 'blue'
EOF
```

## Step 3. 로직 — 툴킷에서 분리 (05의 테스트 가능성)

```bash
cat > src/enforcer.js <<'EOF'
// 순수 로직 — 툴킷 의존 없음 → 단위 테스트 가능 (05)
function findViolations(content) {
  const violations = [];
  const imageRegex = /image:\s*([^\s]+)/g;
  let m;
  while ((m = imageRegex.exec(content)) !== null) {
    const ref = m[1];
    // 다이제스트(@sha256:)가 아니고, 태그(:...)를 쓰면 위반
    if (!ref.includes('@sha256:') && ref.includes(':')) {
      violations.push(ref);
    }
  }
  return violations;
}
module.exports = { findViolations };
EOF

cat > src/index.js <<'EOF'
const core = require('@actions/core');
const fs = require('fs');
const path = require('path');
const { findViolations } = require('./enforcer');

try {
  const target = core.getInput('path');          // 03: core가 입력을 안전 처리
  const failOnTag = core.getInput('fail-on-tag') === 'true';

  let files = [];
  if (fs.statSync(target).isDirectory()) {
    files = fs.readdirSync(target).filter(f => f.endsWith('.yaml') || f.endsWith('.yml'))
              .map(f => path.join(target, f));
  } else {
    files = [target];
  }

  let total = [];
  for (const f of files) {
    const v = findViolations(fs.readFileSync(f, 'utf8'));
    v.forEach(ref => core.warning(`${f}: 태그 참조 발견 '${ref}' (다이제스트를 쓰세요 — 04)`));
    total = total.concat(v);
  }

  core.setOutput('violations', total.length);
  core.info(`검사 완료: ${files.length}개 파일, ${total.length}개 위반`);

  if (failOnTag && total.length > 0) {
    core.setFailed(`${total.length}개의 이미지가 태그로 참조됨 — 다이제스트(@sha256) 필요`);
  }
} catch (e) {
  core.setFailed(e.message);
}
EOF
```

✅ **로직(enforcer.js)을 툴킷(index.js)에서 분리** — 05의 아이스크림 콘 회피(순수 함수는 단위 테스트, 툴킷 통합은 얇게).

## Step 4. 테스트 (05의 원리)

```bash
cat > __tests__/enforcer.test.js <<'EOF'
const { findViolations } = require('../src/enforcer');

test('다이제스트는 통과', () => {
  const yaml = 'image: app@sha256:abc123';
  expect(findViolations(yaml)).toHaveLength(0);
});

test('태그는 위반', () => {
  const yaml = 'image: app:v1.2.3';
  expect(findViolations(yaml)).toEqual(['app:v1.2.3']);
});

test('여러 이미지 혼합', () => {
  const yaml = `
    image: good@sha256:abc
    image: bad:latest
    image: alsobad:v2`;
  expect(findViolations(yaml)).toHaveLength(2);
});
EOF

cat > jest.config.js <<'EOF'
module.exports = { testEnvironment: 'node' };
EOF
npx jest 2>&1 | tail -6
```

예상: 3 passed. ✅ 로직을 순수 함수로 분리했기에 러너·툴킷 없이 초 단위 테스트(05).

## Step 5. 번들링 — dist 생성 (theory §3)

```bash
npx ncc build src/index.js -o dist 2>&1 | tail -2
ls -la dist/index.js    # node_modules가 번들된 단일 파일
```

✅ `dist/index.js` 하나에 모든 의존성 — 소비자는 npm install 없이 실행. action.yml의 `main: 'dist/index.js'`가 이것을 가리킵니다.

## Step 6. 로컬 테스트 — 실제 워크플로에서

```bash
mkdir -p .github/workflows manifests
cat > manifests/good.yaml <<'EOF'
image: myapp@sha256:1111111111111111111111111111111111111111111111111111111111111111
EOF
cat > manifests/bad.yaml <<'EOF'
image: myapp:latest
image: other:v1.2.3
EOF

cat > .github/workflows/test-action.yml <<'EOF'
name: test-action
on: [push, workflow_dispatch]
jobs:
  enforce:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Digest 검증 (내가 만든 액션)
        id: check
        uses: ./                          # 로컬 액션 (같은 저장소)
        continue-on-error: true
        with:
          path: manifests
          fail-on-tag: 'true'
      - name: 결과
        run: echo "위반 ${{ steps.check.outputs.violations }}개 감지됨"
EOF

git add -A && git commit -qm "feat: digest enforcer action"
gh repo create cicd-lab-action --public --source=. --push >/dev/null
sleep 60
gh run view --log 2>/dev/null | grep -E "태그 참조 발견|위반|감지됨" | head -5
```

예상: bad.yaml의 두 이미지가 위반으로 감지되고, 워크플로가 실패(또는 continue-on-error로 계속). ✅ **내가 만든 액션이 04의 규율을 CI 게이트로 강제**합니다 — 소비에서 생산으로.

## Step 7. 산출물

```markdown
# 액션 개발 체크리스트
- [x] action.yml: 입력/출력/branding 명확
- [x] 로직을 툴킷에서 분리 (테스트 가능 — 05)
- [x] 단위 테스트 (순수 함수)
- [x] ncc 번들 → dist 커밋
- [x] 로컬 워크플로에서 통합 테스트 (uses: ./)
- [ ] lab-02: 버전 태그, 마켓플레이스, 공급망 안전
```

## 정리

lab-02에서 배포와 공급망을 다룹니다. 저장소 유지.
