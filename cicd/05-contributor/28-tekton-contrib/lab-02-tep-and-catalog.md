# Lab 02 — TEP 읽기, catalog 기여, k8s식 프로세스 실전

설계 사료(TEP)를 읽는 법, 가장 낮은 문(catalog)으로 기여하는 법, Prow 프로세스에서 첫 PR이 겪는 일을 연습합니다.

전제: lab-01 완료, gh CLI.

## Step 1. TEP 탐색 — 16의 상처가 논의된 흔적 찾기

```bash
cd ~/contrib
git clone --depth 20 https://github.com/tektoncd/community.git && cd community
ls teps/ | head -10

# 16에서 겪은 불편으로 검색 — "이미 논의됐는가"
grep -rln "workspace" teps/ | head -5
grep -rln "param.*propagat\|propagated param" teps/ | head -3
```

TEP 하나를 골라 구조를 관찰(Summary→Motivation→Proposal→Alternatives→상태). ✅ **기여 전 TEP 검색은 예의이자 지름길** — 내 아이디어의 선행 논의·기각 사유·구현 상태가 여기 있습니다(26의 ADR, 27의 proposals와 같은 지위).

## Step 2. Prow 프로세스 관찰 — 머지가 어떻게 일어나나

```bash
# 최근 머지된 PR에서 라벨·코멘트의 흐름 관찰
gh pr list -R tektoncd/pipeline --state merged --limit 5 --json number,title,labels \
  --jq '.[] | "\(.number)  \(.title)  [\([.labels[].name] | select(length>0) | join(","))]"'

# lgtm/approved 라벨의 실물
gh pr view $(gh pr list -R tektoncd/pipeline --state merged --limit 1 --json number -q '.[0].number') \
  -R tektoncd/pipeline --json labels -q '[.labels[].name] | join(", ")'
```

예상: `lgtm`, `approved`, `ok-to-test` 라벨들 — k8s 43에서 배운 Prow 문법의 실물. ✅ 첫 PR 시나리오를 미리 알기: 외부 기여자의 PR은 유지보수자의 `/ok-to-test`까지 CI가 대기(03의 포크 신뢰 경계) → 리뷰어 `/lgtm` → OWNERS의 `/approve` → 자동 머지.

## Step 3. OWNERS 읽기 — 내 리뷰어를 미리 아는 법

```bash
cd ~/contrib/pipeline
cat OWNERS 2>/dev/null | head -15 || cat OWNERS_ALIASES 2>/dev/null | head -15
find . -name OWNERS -not -path "./vendor/*" | head -5
```

✅ 디렉터리별 OWNERS가 곧 "이 코드의 리뷰어 명단" — PR 전에 그들의 최근 리뷰 스타일(어떤 코멘트를 다는지)을 훑으면 왕복이 줄어듭니다(k8s 43의 실전 적용).

## Step 4. catalog — 가장 낮은 문으로 기여 연습

18의 Digest Enforcer(액션)를 Tekton Task로 이식해봅시다 — 생산자 경험의 이식:

```bash
mkdir -p ~/contrib/my-catalog-task/digest-enforcer/0.1 && cd ~/contrib/my-catalog-task/digest-enforcer/0.1
cat > digest-enforcer.yaml <<'EOF'
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: digest-enforcer
  labels: { app.kubernetes.io/version: "0.1" }
  annotations:
    tekton.dev/pipelines.minVersion: "0.50.0"
    tekton.dev/categories: Security
    tekton.dev/tags: "security, supply-chain"
    tekton.dev/displayName: "Digest Enforcer"
spec:
  description: >-
    매니페스트의 이미지 참조가 다이제스트(@sha256)를 쓰는지 검증합니다.
    태그 참조 발견 시 실패합니다 (불변성 강제 — 공급망 규율).
  params:
    - name: path
      description: 검사할 매니페스트 디렉터리
      default: "."
  workspaces:
    - name: source
      description: 매니페스트가 있는 워크스페이스
  steps:
    - name: enforce
      image: alpine@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1  # ★ 다이제스트 고정 (04 — 심사 기준!)
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/sh
        set -e
        VIOLATIONS=$(grep -rhoE "image:\s*\S+" "$(params.path)" 2>/dev/null \
          | grep -v "@sha256:" | grep ":" | wc -l)
        echo "태그 참조 위반: ${VIOLATIONS}건"
        [ "$VIOLATIONS" -eq 0 ] || { echo "🚨 다이제스트(@sha256)를 쓰세요"; exit 1; }
EOF

# 로컬 검증 — lab-01 클러스터에서
kubectl apply -f digest-enforcer.yaml && kubectl get task digest-enforcer
```

✅ catalog 기여의 형식이 갖춰졌습니다: 버전 디렉터리, 카테고리 주석, 파라미터·workspace 문서화, **스텝 이미지의 다이제스트 고정**(04의 규율이 심사 기준이 되는 것을 실감). 실제 제출은 tektoncd/catalog의 recommendations.md 체크리스트 + README + 테스트를 채워 PR.

## Step 5. 첫 이슈 후보 훑기 — 세 저장소의 온도

```bash
for R in tektoncd/pipeline tektoncd/cli tektoncd/dashboard; do
  GFI=$(gh api "search/issues?q=repo:$R+is:issue+is:open+label:\"good first issue\"" -q .total_count)
  echo "$R  good-first-issue: $GFI"
  sleep 2
done
gh issue list -R tektoncd/pipeline --label "good first issue" --limit 5 --json number,title \
  --jq '.[] | "\(.number)  \(.title)"'
```

✅ cli(UX 개선·플래그 추가)와 dashboard(TS)가 상대적으로 진입이 쉽고, pipeline 본진은 lab-01의 추적 경험이 있어야 안전합니다 — 26·27과 같은 "문 고르기"를 데이터로.

## Step 6. 산출물 — 기여자 트랙 졸업 카드 (26~28 종합)

```markdown
# 세 생태계, 세 전략 (이 트랙에서 배운 것)
| | 26 actions/runner | 27 argoproj | 28 tektoncd |
|---|---|---|---|
| 거버넌스 | 기업(GitHub) | CNCF Graduated | CDF + k8s 프로세스 |
| 개발 루프 | 로컬 빌드 + _diag | make start-local | ko apply |
| 합의 형식 | ADR(읽기 전용에 가까움) | proposal | TEP |
| 첫 문 | 재현·진단 이슈 | docs/UI | catalog(YAML) |
| 공통 문법 | 재현 테스트 → 수정 → 리뷰 대응 (k8s 44·45) — 어디서나 동일 |

# 다음 행동 (하나를 고릅니다)
- [ ] 16의 불편 하나 → TEP 검색 → 이슈 코멘트 or 새 이슈
- [ ] catalog에 Step 4의 Task를 규칙대로 완성해 제출
- [ ] cli의 good first issue 하나 → 재현 → PR
★ cncf 파트에서 이 기여 문법을 CNCF 생태계 전체(landscape)로 확장합니다
```

## 정리

```bash
bash cleanup.sh
```
