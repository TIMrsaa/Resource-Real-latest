# Lab 02 — Game Day: 부러진 파이프라인 4종 수리 훈련

k8s 36의 Game Day처럼 — 답을 보기 전에 3질문 분류(theory §1)와 카드로 스스로 진단하세요. 각 시나리오는 "증상만" 먼저 주어집니다.

전제: lab-01의 저장소(~/ci-lab/trouble).

## 준비 — 부러진 워크플로 4종 설치

```bash
cd ~/ci-lab/trouble && mkdir -p .github/workflows

# 시나리오 A
cat > .github/workflows/broken-a.yml <<'EOF'
name: broken-a
on: [workflow_dispatch]
permissions: { contents: read }
jobs:
  affected:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: 변경된 파일 계산
        run: |
          git diff --name-only HEAD~1 || exit 1
EOF

# 시나리오 B
cat > .github/workflows/broken-b.yml <<'EOF'
name: broken-b
on: [workflow_dispatch]
permissions: { contents: read }
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix: { shard: [1, 2, 3] }
    steps:
      - name: 샤드 ${{ matrix.shard }} 테스트
        run: |
          [ "${{ matrix.shard }}" = "2" ] && sleep 3 && exit 1
          sleep 30 && echo "shard ${{ matrix.shard }} pass"
EOF

# 시나리오 C
cat > .github/workflows/broken-c.yml <<'EOF'
name: broken-c
on: [workflow_dispatch]
permissions: { contents: read }
jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: 테스트 실행
        run: |
          mkdir -p results
          echo "no tests found matching '**/*.spec.js'" 
          echo '<testsuite tests="0" failures="0"/>' > results/junit.xml
      - name: 결과 판정
        run: |
          grep -q 'failures="0"' results/junit.xml && echo "✅ 테스트 통과!"
EOF

# 시나리오 D
cat > .github/workflows/broken-d.yml <<'EOF'
name: broken-d
on: [workflow_dispatch]
permissions: { contents: read }
jobs:
  build:
    runs-on: ubuntu-latest
    container: node:20
    steps:
      - uses: actions/checkout@v4
      - name: 빌드 산출물 생성
        run: mkdir -p dist && echo "built" > dist/app.js
  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: 산출물 배포
        run: cat dist/app.js
EOF

git add -A && git commit -qm "game day: broken workflows" && git push -q
for W in broken-a broken-b broken-c broken-d; do gh workflow run $W; sleep 5; done
sleep 90
```

---

## 시나리오 A — "affected 계산이 실패한다"

```bash
gh run list --workflow=broken-a --limit 1   # 실패 확인
gh run view $(gh run list --workflow=broken-a --limit 1 --json databaseId -q '.[0].databaseId') --log 2>/dev/null | tail -3
```

**증상**: `fatal: bad revision 'HEAD~1'` 류. 항상 실패, 이 워크플로만. 무엇이 변했나 — 아무것도(처음부터 안 됨).

<details><summary>진단과 수리 (먼저 스스로)</summary>

카드 없음 → 3질문 → "항상+정의 문제". checkout의 기본 `fetch-depth: 1` — HEAD~1이 존재하지 않습니다(20의 함정 재등장). 수리:

```bash
sed -i 's|- uses: actions/checkout@v4|- uses: actions/checkout@v4\n        with: { fetch-depth: 0 }|' \
  .github/workflows/broken-a.yml
```
</details>

## 시나리오 B — "실패 원인이 안 보인다"

```bash
gh run view $(gh run list --workflow=broken-b --limit 1 --json databaseId -q '.[0].databaseId') 2>/dev/null | head -10
```

**증상**: 매트릭스 3개 중 shard 2가 실패 — 그런데 1·3도 **cancelled**로 끝나 "뭐가 문제인지" 로그가 절반뿐입니다.

<details><summary>진단과 수리</summary>

`fail-fast`의 기본값 true — 하나가 실패하면 나머지를 취소합니다. 빠른 피드백에는 좋지만 **진단 정보를 지웁니다**(간헐 실패 사냥 중이면 치명적 — 카드 6의 확인을 방해). 수리(진단 모드):

```bash
sed -i 's|strategy:|strategy:\n      fail-fast: false|' .github/workflows/broken-b.yml
```
평시 fail-fast: true(비용 절약) ↔ flaky 사냥 때 false — 목적에 따른 스위치임을 이해하는 것이 포인트.
</details>

## 시나리오 C — "테스트가 통과했습니다... 정말?"

```bash
gh run view $(gh run list --workflow=broken-c --limit 1 --json databaseId -q '.[0].databaseId') --log 2>/dev/null | grep -E "no tests|통과"
```

**증상**: 초록불. 로그를 자세히 보면 `no tests found` — **0건 실행**인데 `failures="0"`이라 통과 판정. 거짓 초록(카드 9의 사촌)입니다.

<details><summary>진단과 수리</summary>

글롭 오타(`.spec.js` vs 실제 `.test.js`)류로 테스트가 0건 수집 — "실패 0 = 성공"의 논리 구멍. 수리 — **최소 실행 수 게이트**:

```bash
sed -i 's|grep -q .failures=.0.. results/junit.xml && echo "✅ 테스트 통과!"|TESTS=$(grep -oE '"'"'tests="[0-9]+"'"'"' results/junit.xml \| grep -oE "[0-9]+"); [ "$TESTS" -gt 0 ] \|\| { echo "🚨 테스트 0건 실행 — 수집 글롭 확인"; exit 1; }; grep -q '"'"'failures="0"'"'"' results/junit.xml \&\& echo "✅ ${TESTS}건 통과"|' .github/workflows/broken-c.yml
```
"성공"의 정의에 **최소 조건**(N건 이상 실행)을 넣어라 — 커버리지 급락 경보(05)와 같은 계열의 백신.
</details>

## 시나리오 D — "빌드는 됐는데 배포할 게 없다"

```bash
gh run view $(gh run list --workflow=broken-d --limit 1 --json databaseId -q '.[0].databaseId') --log 2>/dev/null | tail -3
```

**증상**: release 잡이 `cat: dist/app.js: No such file` — build는 초록인데.

<details><summary>진단과 수리</summary>

**잡은 각각 새 러너**입니다(03의 실행 모델·격리 경계) — build 잡의 파일시스템은 release 잡에 존재하지 않습니다. 아티팩트로 명시적 전달이 필요:

```bash
python3 - <<'EOF'
import re
p = '.github/workflows/broken-d.yml'
s = open(p).read()
s = s.replace("""      - name: 빌드 산출물 생성
        run: mkdir -p dist && echo "built" > dist/app.js""",
"""      - name: 빌드 산출물 생성
        run: mkdir -p dist && echo "built" > dist/app.js
      - uses: actions/upload-artifact@v4
        with: { name: dist, path: dist/ }""")
s = s.replace("""      - name: 산출물 배포
        run: cat dist/app.js""",
"""      - uses: actions/download-artifact@v4
        with: { name: dist, path: dist/ }
      - name: 산출물 배포
        run: cat dist/app.js""")
open(p,'w').write(s)
EOF
```
"needs는 순서만 보장하지 데이터는 전달하지 않는다" — 03의 실행 모델이 진단의 근거였습니다.
</details>

## 마무리 — 수리 검증과 회고

```bash
git add -A && git commit -qm "game day: all fixed" && git push -q
for W in broken-a broken-b broken-c broken-d; do gh workflow run $W; sleep 5; done
sleep 90
gh run list --limit 4 --json name,conclusion -q '.[] | "\(.name): \(.conclusion)"'
```

예상: A·C·D success, B는 shard 2 실패가 **보이는 채로** 실패(진단 가능해진 것이 수리 목표였습니다).

```markdown
# Game Day 회고 (팀 훈련이라면)
- 각 시나리오에서 3질문 분류까지 걸린 시간은?
- 로그의 어느 줄이 결정적 단서였나요? (그 줄을 더 빨리 보는 법은?)
- 각 수리의 "예방 게이트"는 무엇인가요? → 24의 정책으로 코드화할 것
- 우리 실제 파이프라인에 A~D와 같은 급소가 있는가요? (특히 C — 0건 통과)
```

## 정리

```bash
bash cleanup.sh
```
