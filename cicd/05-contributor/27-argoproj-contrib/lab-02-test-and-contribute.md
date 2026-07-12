# Lab 02 — 테스트 문법, 이슈 탐색, 그리고 기여 경로 설계

버그 수정 PR의 형식(재현 테스트 먼저)을 연습하고, argoproj의 열린 문들을 데이터로 훑습니다.

전제: lab-01 완료(~/contrib/argo-cd, kind 클러스터).

## Step 1. 단위 테스트 문화 확인 — 비교 로직의 테스트

```bash
cd ~/contrib/argo-cd
ls controller/*_test.go | head -5
go test ./controller/ -run TestCompareAppState -count=1 2>&1 | tail -3
```

예상: 통과. 테스트 하나를 열어 구조를 관찰:

```bash
grep -n "func TestCompareAppState" controller/state_test.go | head -3
grep -n "newFakeController\|fake\." controller/state_test.go | head -5
```

✅ **fake 데이터로 컨트롤러를 만들어 비교 결과를 단정**하는 패턴(k8s 44의 fake client 문법) — 버그 수정 PR은 이 형식의 "실패하는 테스트"를 먼저 추가하는 것으로 시작합니다.

## Step 2. 재현 테스트 작성 연습 — 가상의 버그로 형식 익히기

14의 함정(무시해야 할 필드가 diff를 냅니다)을 소재로, 테스트 형식만 연습합니다:

```bash
cat > /tmp/practice_test_shape.md <<'EOF'
# 버그 수정 PR의 뼈대 (argo-cd 관례)
1. controller/state_test.go 에 재현 테스트 추가:
   func TestCompareAppState_IgnoresManagedFieldX(t *testing.T) {
     // given: 기대 상태와 실제 상태가 field X만 다름
     // when:  CompareAppState
     // then:  Synced 여야 함 — 현재는 OutOfSync (버그 재현!)
   }
2. go test ./controller/ -run TestCompareAppState_Ignores... → 빨강 확인
3. 수정 (state.go 또는 gitops-engine — 경계 판정!)
4. 같은 테스트 → 초록. 기존 테스트 전체 → 여전히 초록 (회귀 없음)
5. PR 본문: 재현 → 원인 → 수정 → 테스트 (이슈 번호 연결)
EOF
cat /tmp/practice_test_shape.md
```

✅ "테스트가 빨강→초록이 되는 것"이 곧 PR의 증명입니다 — 리뷰어가 재현·검증에 쓸 시간을 0으로.

## Step 3. e2e 감각 — 어떤 것이 e2e 대상인가

```bash
ls test/e2e/ | head -8
grep -rn "func TestSyncWithWave\|wave" test/e2e/*_test.go 2>/dev/null | head -3
echo "→ sync wave·hook처럼 '실제 클러스터의 순서'가 본질인 것은 e2e — 단위로는 못 담는다"
echo "   (전부 e2e로 하면 느려서 못 돕니다 — 05의 피라미드가 컨트롤러 저장소에도)"
```

## Step 4. 이슈 탐색 — 4형제의 온도와 good first issue

```bash
for R in argoproj/argo-cd argoproj/argo-rollouts argoproj/gitops-engine; do
  GFI=$(gh api "search/issues?q=repo:$R+is:issue+is:open+label:\"good first issue\"" -q .total_count)
  HELP=$(gh api "search/issues?q=repo:$R+is:issue+is:open+label:\"help wanted\"" -q .total_count 2>/dev/null || echo -)
  echo "$R  good-first-issue:$GFI  help-wanted:$HELP"
  sleep 2
done

# 내 지식과 겹치는 이슈 찾기 — 14·17의 키워드로
gh issue list -R argoproj/argo-cd --search "sync wave" --limit 5 --json number,title \
  --jq '.[] | "\(.number)  \(.title)"'
gh issue list -R argoproj/argo-rollouts --search "analysis" --limit 5 --json number,title \
  --jq '.[] | "\(.number)  \(.title)"'
```

✅ 사용자로 배운 주제(sync wave, AnalysisTemplate)의 이슈가 실제로 열려 있습니다 — **14·17의 지식이 이슈를 "읽을 수 있는" 자격**이 된 것을 확인.

## Step 5. Rollouts 문 — 17의 회수

```bash
cd ~/contrib && git clone --depth 20 https://github.com/argoproj/argo-rollouts.git && cd argo-rollouts
ls rollout/                                   # 컨트롤러 — canary/bluegreen 단계 로직
grep -rn "func.*nextStep\|CurrentStepIndex" rollout/*.go | head -3
ls analysis/                                  # 17의 AnalysisRun 컨트롤러
ls rollout/trafficrouting/                    # istio, alb(eks 14!), nginx ... 제공자별
```

✅ 17에서 운영한 카나리 스텝·분석·트래픽 전환이 패키지 셋으로 그대로 — **trafficrouting/ 제공자 추가·수정**은 경계가 명확해 첫 코드 기여로 인기 있는 영역입니다.

## Step 6. 문서·proposal — 코드 밖의 두 문

```bash
cd ~/contrib/argo-cd
ls docs/proposals/ | head -5                  # 설계 제안의 실물 (KEP의 argo판)
grep -rn "argocd.argoproj.io/refresh" docs/ -l | head -3
echo "→ 14에서 헤맨 것(문서가 부족했던 지점)이 곧 문서 기여 후보다"
echo "→ 큰 변경은 proposals/에 문서 PR부터 — 설계 합의가 코드보다 먼저 (k8s 45)"
```

## Step 7. 산출물 — 4주 기여 계획 (26의 양식 재사용)

```markdown
# argoproj 기여 계획
- 문: (docs / UI(TS) / rollouts trafficrouting / controller / gitops-engine) — Step 4 온도 + 내 언어
- 1주: developer-guide 정독 + start-local 루프 몸에 붙이기(lab-01) + 기여자 미팅 캘린더 확인
- 2주: 14·17 경험과 겹치는 이슈에 재현 코멘트 (fake client 테스트 형식으로 — Step 2)
- 3주: good first issue PR (재현 테스트 → 수정 → 회귀 확인)
- 4주: 리뷰 대응 + (겨냥) 다음 마일스톤 확인
- 주의: 수정이 gitops-engine 국경 너머면 2단계 여정(engine PR → argo-cd 의존 갱신) 계획
```

## 정리

```bash
bash cleanup.sh
```
