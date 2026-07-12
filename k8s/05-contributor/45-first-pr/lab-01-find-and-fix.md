# Lab 01 — 이슈 선택과 수정 작업 (실전 절차서 전반부)

> 이 lab은 "따라 치면 끝"이 아니라 **실전을 위한 절차서**입니다. 각 Step을 실제 이슈에 적용하세요. 예시는 가상의 이슈로 시연합니다.

## Step 0. 출발 점검 (43의 산출물)

```markdown
- [ ] CLA 서명됨  - [ ] fork 존재 + upstream 리모트 설정(41)  - [ ] 후보 이슈 3개(43 lab-02)
```

## Step 1. 이슈 고르기 — 3분 검증법

후보 이슈마다:

```
① 선점 확인: 코멘트에 /assign 한 사람? 연결된 PR? (Linked PRs 섹션)
   → 있으면 다음 후보로. 단, 수개월 방치된 assign은 "still working on this?"
     코멘트 후 며칠 기다려 양도받을 수 있습니다
② 범위 확인: 이슈에 재현 방법과 기대 동작이 명확한가?
   → "설계 논의 필요해 보임"이면 첫 PR감이 아닙니다
③ 코드 확인: 모듈 42의 전술로 해당 코드를 10분 정찰
   → 수정 위치가 머리에 그려지면 합격
```

✅ 셋 다 통과한 이슈에 선점 선언:

```
코멘트: /assign
(+ 한 줄 인사: "I'd like to work on this. Planning to <접근 한 줄>.")
```

> 본체가 부담스러우면 첫 후보를 kubernetes/website(문서, ko/ 번역 포함)나 kubernetes-sigs/kind에서 — 같은 절차, 빠른 호흡.

## Step 2. 브랜치 준비 (theory §4의 의식)

```bash
cd ~/go/src/k8s.io/kubernetes
git fetch upstream
git switch master && git merge --ff-only upstream/master && git push origin master
git switch -c fix-issue-NNNNN        # 이슈 번호나 내용으로 명명
```

## Step 3. 수정 — 41~44의 총동원 (시연: 가상의 메시지 버그)

가상 이슈: *"kubectl drain의 에러 메시지가 PDB 위반 시 오해를 부릅니다 — 'cannot evict'만 나오고 어느 PDB인지 안 알려줌"*

```bash
# ① 입구 찾기 (42 전술①: 문자열 grep)
grep -rn "cannot evict" staging/src/k8s.io/kubectl/pkg/drain/ 2>/dev/null \
  || grep -rn "Cannot evict" staging/ --include="*.go" | grep -v _test | head -3
# ② 수정: 메시지에 PDB 이름 추가 (에디터에서)
# ③ 테스트 먼저 정신(44): 그 패키지의 기존 테스트에서 메시지를 검증하는 곳 찾기
grep -rn "func Test" staging/src/k8s.io/kubectl/pkg/drain/*_test.go | head -5
# 표에 케이스 추가 → FAIL 확인 → 수정 → PASS
go test ./staging/src/k8s.io/kubectl/pkg/drain/... 2>/dev/null \
  || (cd staging/src/k8s.io/kubectl && go test ./pkg/drain/...)
```

체크리스트:
```markdown
- [ ] 수정이 이슈 범위를 벗어나지 않습니다 (리팩터링 욕구 참기 — 별도 PR감)
- [ ] 테스트 추가/수정 + FAIL→PASS를 봤습니다 (44 §6)
- [ ] 그 패키지 전체 테스트 통과
- [ ] hack/verify-gofmt.sh 통과 (시간 되면 make verify)
```

## Step 4. 커밋 — 규약대로

```bash
git add -p        # 의도한 변경만 (디버그 잔해 제외!)
git commit -m "Include PDB name in drain eviction error message

When eviction is blocked by a PodDisruptionBudget, the error now
includes the PDB name so users can identify which budget blocks
the drain without searching all namespaces.

Fixes #NNNNN"
git log --oneline -2 && git diff master --stat    # 최종 자가 검토
```

✅ 커밋 메시지 3요소: 제목(명령형, 무엇을) / 본문(왜, 어떻게) / `Fixes #이슈`.

## Step 5. push — PR 직전

```bash
git push -u origin fix-issue-NNNNN
```

GitHub이 PR 생성 링크를 출력합니다 — **lab-02에서 계속.**

## 실전용 요약 카드 (이 lab의 산출물)

```markdown
# 첫 PR 전반부 루틴
이슈: 선점확인 → 범위확인 → 코드정찰(10분) → /assign
작업: fetch upstream → 토픽 브랜치 → grep으로 입구 → 테스트 먼저(FAIL) → 수정(PASS)
검수: 범위 준수, 패키지 테스트, verify-gofmt, add -p, 커밋 규약(Fixes #)
```
