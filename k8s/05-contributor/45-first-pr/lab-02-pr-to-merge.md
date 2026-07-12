# Lab 02 — 제출, 리뷰 대응, 머지 (실전 절차서 후반부)

## Step 1. PR 생성 — 템플릿을 성의 있게

push 후 GitHub의 "Compare & pull request"에서. 템플릿 작성 요령:

```markdown
**What type of PR is this?**
/kind bug

**What this PR does / why we need it:**
When `kubectl drain` is blocked by a PDB, the error message did not
say which PDB. This PR includes the PDB name in the message.
(2~4문장. 리뷰어는 이 칸으로 첫인상을 정합니다)

**Which issue(s) this PR fixes:**
Fixes #NNNNN

**Does this PR introduce a user-facing change?**
```release-note
kubectl drain: eviction errors blocked by a PodDisruptionBudget now include the PDB name
```
(사용자 영향 없으면 release-note 블록 안에 NONE — 칸 자체를 비우면 봇이 막습니다)
```

제목: `Include PDB name in drain eviction error` 처럼 변경 요약 (이슈 제목 복붙 금지).

## Step 2. 봇의 세례 읽기 (제출 직후 몇 분)

k8s-ci-robot이 다는 것들:

```
cncf-cla: yes          ← no면 43으로 (서명 문제)
size/S                 ← 첫 PR은 S 이하가 이상적
sig/cli  kind/bug      ← OWNERS/명령 기반 자동 분류
needs-ok-to-test       ← 외부인 첫 PR — 멤버의 승인 대기
```

`needs-ok-to-test`는 정상입니다 — 리뷰어가 보고 `/ok-to-test`를 해주면 CI가 돕니다. 며칠 무반응이면 SIG Slack에 정중히 한 번.

## Step 3. CI 대응 (44에서 훈련한 그대로)

```
초록: 다음 단계 대기
빨강: 로그 → 내 변경 관련성 → (관련) 수정 push / (무관+flake 확증) /retest 한 번
verify 실패: 대부분 gofmt/생성물 — hack/update-* 스크립트 실행 후 push
```

## Step 4. 리뷰 왕복 — 시나리오별 응답 템플릿

**(a) 수정 요구**: 코멘트마다 응답 + 수정은 새 커밋으로 push
```
Done in a1b2c3d. Thanks for catching this!
```

**(b) 이견이 있을 때**: 근거 + 열린 결말
```
I kept the namespace out of the message because it's already in the
error prefix (see line NN). Happy to add it if you think explicit is
better — WDYT?
```

**(c) 모를 때**: 솔직하게 (good first issue는 멘토링 전제)
```
I'm not sure about the convention here — could you point me to an
example of how other commands format this?
```

**(d) squash 요청**:
```bash
git rebase -i upstream/master   # pick → squash로 정리 (로컬에서)
git push -f origin fix-issue-NNNNN
```

**(e) 1~2주 무응답**: PR에 `Gentle ping @reviewer — anything I should improve?` → 1주 더 → SIG Slack.

## Step 5. 머지의 순간

```
리뷰어: /lgtm        → 라벨 lgtm
approver: /approve   → 라벨 approved
→ tide가 머지 큐에서 자동 머지 (마지막 rebase/테스트 포함)
→ 축하. kubernetes/kubernetes의 contributors에 이름이 올랐습니다.
```

머지 후 루틴: 이슈가 자동 클로즈됐는지 확인 → 내 fork의 master 동기화 → 토픽 브랜치 삭제.

## Step 6. 거절/표류 시나리오 (현실 대비)

| 상황 | 대응 |
|------|------|
| "방향이 다름"으로 클로즈 | 이유에 감사 코멘트 → 배움 기록 → 다음 이슈 (평판은 여기서 쌓입니다) |
| "KEP 필요" 판정 | 43의 영역 — 이슈/SIG에서 논의 제안하거나, 더 작은 이슈로 전환 |
| 몇 주째 리뷰어 없음 | SIG Slack 요청 → 그래도 없으면 그 사이 **다른 작은 PR 병행** (한 PR에 매달리지 않기) |
| 다른 PR이 먼저 머지(중복) | 닫고 다음 — /assign 문화가 이걸 줄여주지만 가끔 있습니다 |

## Step 7. 졸업 보고서 (커리큘럼 최종 산출물)

```markdown
# 첫 PR 보고서
- 이슈: #NNNNN (sig-___) / PR: #NNNNN
- 걸린 시간: 정찰 _h, 수정+테스트 _h, 리뷰 왕복 _회/_일
- 막혔던 곳과 해결:
- 리뷰에서 배운 것:
- 다음 기여 후보: (같은 SIG 영역에서 — 리뷰어가 나를 기억합니다)
```

## 그리고 — 커리큘럼 졸업

45개 모듈이 끝났습니다. 이 시점의 당신:
- 클러스터를 **운영**할 수 있고 (01~40)
- 소스를 **빌드·해부·검증**할 수 있고 (41~44)
- 업스트림에 **기여하는 절차**를 압니다 (43, 45)

다음 여정: **eks 파트**(이 지식 위에 AWS 프로덕션 — RPS 실측, 트래픽 처리), 그리고 cicd → cncf. k8s에서 만든 "기여 루프"는 CNCF의 모든 프로젝트에 똑같이 통합니다 — cncf 파트에서 다시 만납니다.
