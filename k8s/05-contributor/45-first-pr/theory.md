# 이론 — PR의 일생과 리뷰의 사회학

> **🌱 17세 눈높이 비유: 학교 신문부에 첫 기사 싣기**
> 아무리 글을 잘 써도 절차가 있습니다: 아이템 회의에서 **선점 선언**(/assign) → 초고(커밋) → **편집장 양식**(PR 템플릿) 맞추기 → 맞춤법 검사기(CI) 통과 → 선배 첨삭(리뷰)에 **기분 상하지 않고** 반영 → 편집장 승인 도장 두 개(lgtm + approve) → 인쇄(머지).
> 첫 기사가 4컷 만평(작은 수정)이어도 — 신문에 이름이 실리는 순간 신문부원입니다.

---

## 1. PR의 일생 (제출 → 머지)

```
이슈에 /assign (선점 선언)
 → fork에서 토픽 브랜치 → 수정+테스트 → 커밋(서명/규약)
 → PR 생성 (템플릿 작성, "Fixes #이슈번호")
 → 봇의 세례: cncf-cla 확인, size/sig 라벨, needs-ok-to-test
 → 멤버가 /ok-to-test → CI(prow) 실행 (모듈 44의 그 잡들)
 → 리뷰어 배정(OWNERS 기반) → 리뷰 왕복 (수정 push)
 → /lgtm (리뷰어: "코드 좋다")
 → /approve (해당 디렉터리 OWNERS의 approver)
 → 두 라벨이 모이면 머지 큐(tide)가 자동 머지
```

### 머지의 두 도장 — lgtm과 approve

| 라벨 | 누가 | 의미 |
|------|------|------|
| `lgtm` | 리뷰어(누구든 멤버) | 코드 품질 OK — 새 push마다 풀립니다 |
| `approved` | 그 디렉터리 OWNERS의 approver | 방향/소유권 승인 — 유지됩니다 |

둘 다 모여야 tide(머지 봇)가 합칩니다. 42에서 본 OWNERS가 여기서 권력으로 작동합니다.

## 2. 커밋과 PR의 규약

```bash
# 커밋: 영어 명령형, 본문에 "왜", 서명은 -s가 필요한 리포에서만 (k/k는 CLA로 갈음)
git commit -m "Fix MaxSurge rounding for fractional percentages

The calculation rounded down when ..., causing ...
This change uses intstr.GetScaledValueFromIntOrPercent with round-up
and adds a regression test case."
```

PR 템플릿의 핵심 칸:
- **What type of PR**: /kind bug, /kind cleanup, /kind documentation...
- **What this PR does / why**: 리뷰어가 처음 읽는 곳 — 이슈 링크(`Fixes #NNNN`)와 함께 2~4문장
- **Does this introduce a user-facing change?**: **release-note 블록** — 사용자 영향 없으면 `NONE` (이거 비우면 봇이 막습니다)

## 3. 리뷰 대응의 기술 (사회학)

### 원칙: 리뷰는 코드에 대한 것이지 나에 대한 것이 아닙니다

- 모든 코멘트에 응답합니다 — 수용이면 "Done" + 수정 push, 이견이면 근거와 함께 정중히 ("I kept X because... WDYT?")
- 모르면 모른다고: "Could you point me to an example?" — 입문자의 질문은 환영받습니다 (good first issue는 멘토링 전제)
- 수정은 **새 커밋으로 push** (리뷰어가 변경분만 보게) — 머지 직전 squash 요청이 오면 그때 정리
- 리뷰어가 1~2주 무응답이면: PR에 정중한 ping → 그래도 없으면 SIG Slack에 "리뷰 부탁" (DM 금지 — 모듈 43)

### 거절(클로즈)을 받았다면

- 이유를 읽습니다 — 대부분 "방향이 KEP과 다름" 또는 "유지보수 비용 > 가치"
- 감사 + 배움 정리 코멘트 → 평판은 **거절에 대응하는 모습**에서 쌓입니다
- 그 에너지로 다음 이슈 — 첫 PR이 거절되는 건 흔하고, 끝이 아닙니다

## 4. fork 운영 — upstream과 동기화

```bash
git remote -v    # origin=내 fork, upstream=kubernetes/kubernetes (41에서 설정)
# 새 작업 전 의식:
git fetch upstream
git switch master && git merge --ff-only upstream/master && git push origin master
git switch -c fix-maxsurge-rounding    # 토픽 브랜치 (main에서 작업 금지 — 41 pitfall)
# PR 후 needs-rebase가 붙으면:
git fetch upstream && git rebase upstream/master && git push -f origin fix-maxsurge-rounding
```

## 5. 첫 머지 이후 — 성장 사다리

```
1~2개 머지     → 같은 SIG 영역에서 계속 (리뷰어가 나를 기억하기 시작)
지속 기여      → org 멤버 신청 (스폰서 2인 — 그간의 리뷰어들) → /ok-to-test 셀프, 이슈 할당 가능
그 다음        → reviewer 등재(OWNERS에 내 아이디!) → approver → ...
병행 경로      → 이슈 트리아지, 리뷰 돕기, flake 사냥, 문서 — 코드만이 기여가 아닙니다
```

K8s의 모든 메인테이너가 이 사다리의 1단(첫 PR)에서 시작했습니다.

## 6. 소스/도구에서 확인하기

- 기여자 가이드(필독): https://www.kubernetes.dev/docs/guide/
- PR 프로세스 상세: contributors/guide/pull-requests.md (community 리포)
- prow 명령 사전: https://prow.k8s.io/command-help
- 멤버십 기준: community/community-membership.md

## 요약 카드

| 질문 | 답 |
|------|----|
| 첫 PR의 목표? | 절차 완주 (크기는 작을수록 좋습니다) |
| 머지 조건? | lgtm + approved (tide가 자동 머지) |
| release-note 칸? | 사용자 영향 없으면 `NONE` — 비우면 차단 |
| 리뷰 무응답 시? | PR에서 ping → SIG Slack (DM 금지) |
| 거절당하면? | 이유에서 배우고 다음 이슈 — 평판은 대응에서 쌓입니다 |
| 다음 단계? | 같은 영역 반복 → org 멤버 → reviewer |
