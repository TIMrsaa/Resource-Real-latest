# Lab 02 — 테스트를 먼저, 그리고 첫 PR

기여의 실체는 코드가 아니라 **테스트 + 소통**입니다. 클러스터 없이 도는 단위 테스트를 읽고·쓰고, 첫 PR의 전 과정을 리허설합니다.

## Step 1. 테스트가 도는 것을 먼저 봅니다

```bash
cd ~/kp/core
# 스케줄링 시뮬레이터의 테스트 — fake client라 클러스터 불필요, 초 단위
go test ./pkg/controllers/provisioning/... -count=1 2>&1 | tail -5

# consolidation 테스트 (17 lab-02의 그 동작이 코드로 명세돼 있습니다)
go test ./pkg/controllers/disruption/... -count=1 2>&1 | tail -5
```

## Step 2. 테스트를 읽으면 스펙이 보입니다

```bash
grep -n "It(\"should" pkg/controllers/disruption/consolidation_test.go | head -12
```

예상 출력의 성격:

```
It("should not consolidate when a pod has do-not-disrupt annotation" ...
It("should consolidate to a cheaper instance type" ...
```

✅ **테스트 이름이 곧 제품 명세**입니다 — 17에서 사용자로 관찰한 동작들이 여기 문장으로 박혀 있습니다. 새 기여를 할 때 "이 동작이 이미 명세돼 있나"를 여기서 먼저 확인합니다.

## Step 3. 실습: 엣지 케이스 테스트 하나 추가하기

좋은 첫 기여 유형 ②(테스트 보강 — theory §7). 기존 테스트를 본떠 하나 써봅니다:

```bash
# 픽스처 헬퍼 익히기
grep -n "func ExpectScheduled\|func ExpectApplied\|func ExpectProvisioned" pkg/test/expectations/expectations.go | head
```

```go
// 예시 (pkg/controllers/provisioning/scheduling/scheduling_test.go 스타일)
It("should not provision when the pod requires an instance type excluded by the NodePool", func() {
    nodePool.Spec.Template.Spec.Requirements = []v1.NodeSelectorRequirementWithMinValues{{
        NodeSelectorRequirement: corev1.NodeSelectorRequirement{
            Key: corev1.LabelInstanceTypeStable, Operator: corev1.NodeSelectorOpIn,
            Values: []string{"small-instance-type"},
        }}}
    pod := test.UnschedulablePod(test.PodOptions{
        NodeSelector: map[string]string{corev1.LabelInstanceTypeStable: "large-instance-type"},
    })
    ExpectApplied(ctx, env.Client, nodePool, pod)
    ExpectProvisioned(ctx, env.Client, cluster, cloudProvider, prov, pod)
    ExpectNotScheduled(ctx, env.Client, pod)     // 교집합이 공집합 → 노드 없음
})
```

```bash
go test ./pkg/controllers/provisioning/scheduling/... -count=1 -run TestScheduling 2>&1 | tail -3
```

✅ 이 테스트가 검증하는 것은 theory §4의 **교집합 대수**입니다 — Pod 요구 ∩ NodePool requirements = ∅ 이면 노드가 생기지 않습니다. 사용자 지식(17)이 테스트가 되는 순간.

## Step 4. 첫 이슈 고르기

```bash
gh issue list --repo kubernetes-sigs/karpenter --label "good first issue" --state open --limit 10 \
  --json number,title,createdAt --jq '.[] | "#\(.n // .number)  \(.title)"'
gh issue list --repo aws/karpenter-provider-aws --label "good first issue" --state open --limit 10 \
  --json number,title --jq '.[] | "#\(.number)  \(.title)"'
```

고르기 전 확인:

```markdown
- [ ] 이미 다른 사람이 assign됐거나 PR이 열려 있지 않은가 (댓글 확인)
- [ ] 저장소 판정이 맞는가 (코어 vs 프로바이더 — theory §1)
- [ ] 재현할 수 있는가 (못 하면 다른 이슈로)
- [ ] 이슈에 의사 표명 댓글을 남겼는가 ("I'd like to work on this")
```

## Step 5. PR 워크플로 리허설

```bash
cd ~/kp/core
git checkout -b test/scheduling-edge-case
# ... 변경 ...
git add -A
git commit -s -m "test: add coverage for empty instance type intersection"    # ★ -s = DCO 서명

# CI를 로컬에서 미리 통과시킵니다 (리뷰어의 시간을 아끼는 예의)
make verify       # 포맷·린트·생성물 검증
make test         # 단위 테스트

# replace 지시자 잔재 확인! (lab-01의 사고)
git diff origin/main -- go.mod go.sum

gh pr create --repo kubernetes-sigs/karpenter --fill \
  --title "test: add coverage for empty instance type intersection" \
  --body "Adds a scheduling test asserting that a pod is not scheduled when its instance-type selector has no intersection with the NodePool requirements.

Fixes #<이슈번호>

/kind cleanup"
```

머지까지의 문법(k8s 45와 동일 — prow 봇):

```
CI 통과 → 리뷰어가 코멘트 → 반영(커밋 추가) → 리뷰어 `/lgtm` → approver `/approve` → 자동 머지
막히면: `/retest` (플레이키 CI), `/assign @user`, `/hold`(머지 보류)
```

## Step 6. 리뷰 대응의 기술

```markdown
# 리뷰 피드백 대응 원칙
- 리뷰는 선물입니다 — "왜 이렇게 안 했나"는 공격이 아니라 맥락 질문입니다
- 동의하면: 반영 + "Done" 한 줄. 동의 안 하면: 근거를 제시하되 결정권은 메인테이너에게
- 침묵 대신 상태 표시: 며칠 걸릴 것 같으면 "Working on it, will push by Friday"
- force-push로 리뷰 이력을 지우지 말 것 (커밋을 쌓고, 머지 시 스쿼시)
- 첫 PR이 안 받아들여져도 — 그 스레드에서 배운 맥락이 다음 PR을 통과시킵니다
```

## Step 7. 기여 로드맵 (산출물)

```markdown
# 나의 Karpenter 기여 계획
- [ ] 0층: 워킹그룹 미팅 노트 구독, 릴리스 노트 읽기 (맥락)
- [ ] 1층: 사용 중 만난 마찰을 이슈로 (27의 이슈 작성법)
- [ ] 2층: 문서 PR 1건 (NodePool 필드 설명, 예제 오류)
- [ ] 3층: 테스트 PR 1건 (이 랩의 Step 3)
- [ ] 4층: good-first-issue 버그픽스 1건 (테스트 포함 필수)
- [ ] 5층: 관측성 개선 — "왜 이 타입을 골랐나"를 이벤트로 노출 (내가 lab-01에서 아쉬웠던 것!)
```

## 정리

```bash
bash cleanup.sh
```
