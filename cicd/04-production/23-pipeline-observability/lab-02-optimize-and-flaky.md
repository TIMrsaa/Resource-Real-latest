# Lab 02 — critical path 최적화와 flaky 자동 탐지

일부러 느리게 만든 파이프라인을 측정 → 경로 분석 → 최적화하고, 재시도 이력에서 flaky를 탐지하는 리포트를 만듭니다.

전제: lab-01의 저장소(~/ci-lab/observ).

## Step 1. 느린 파이프라인 — 순차 + 캐시 없음

```bash
cd ~/ci-lab/observ
cat > .github/workflows/slow.yml <<'EOF'
name: slow
on: [workflow_dispatch]
permissions: { contents: read }
jobs:
  lint:
    runs-on: ubuntu-latest
    steps: [{ run: sleep 20 }]
  unit:
    needs: lint                    # ← 정말 lint를 기다려야 하나요?
    runs-on: ubuntu-latest
    steps: [{ run: sleep 45 }]
  integration:
    needs: unit                    # ← 정말 unit을 기다려야 하나요?
    runs-on: ubuntu-latest
    steps: [{ run: sleep 70 }]
  build:
    needs: integration
    runs-on: ubuntu-latest
    steps: [{ run: sleep 30 }]
EOF
git add -A && git commit -qm "slow pipeline" && git push -q
gh workflow run slow && sleep 200
```

## Step 2. 측정 — 잡별 시간과 critical path

```bash
RUN_ID=$(gh run list --workflow=slow --limit 1 --json databaseId -q '.[0].databaseId')
gh api "repos/{owner}/{repo}/actions/runs/$RUN_ID/jobs" --jq '
  .jobs[] | "\(.name): \((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))초"'
gh run view $RUN_ID --json createdAt,updatedAt --jq \
  '"전체: \((.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601))초"'
```

예상: lint 20 + unit 45 + integration 70 + build 30 ≈ **전체 165초+** — 전부 순차라 경로가 곧 전체입니다. 그래프를 그려보면:

```
lint(20) → unit(45) → integration(70) → build(30)   critical path = 165초
질문: 이 화살표(needs) 중 "진짜 의존"은 몇 개인가요?
  - unit이 lint를 기다릴 이유: 없음 (독립 검사)
  - integration이 unit을 기다릴 이유: 없음 (다른 종류의 검사)
  - build가 테스트를 기다릴 이유: 게이트 목적이면 있음 — 단 "테스트들"이지 순차일 필요 없음
```

## Step 3. 최적화 — 가짜 의존 제거

```bash
cat > .github/workflows/slow.yml <<'EOF'
name: slow
on: [workflow_dispatch]
permissions: { contents: read }
jobs:
  lint:
    runs-on: ubuntu-latest
    steps: [{ run: sleep 20 }]
  unit:
    runs-on: ubuntu-latest          # needs 제거 — 병렬
    steps: [{ run: sleep 45 }]
  integration:
    runs-on: ubuntu-latest          # needs 제거 — 병렬
    steps: [{ run: sleep 70 }]
  build:
    needs: [lint, unit, integration]  # 게이트는 유지 — 그러나 셋을 "동시에" 기다림
    runs-on: ubuntu-latest
    steps: [{ run: sleep 30 }]
EOF
git add -A && git commit -qm "parallelize: remove false dependencies" && git push -q
gh workflow run slow && sleep 150

RUN_ID=$(gh run list --workflow=slow --limit 1 --json databaseId -q '.[0].databaseId')
gh run view $RUN_ID --json createdAt,updatedAt --jq \
  '"최적화 후 전체: \((.updatedAt | fromdateiso8601) - (.createdAt | fromdateiso8601))초"'
```

예상: max(20,45,70) + 30 ≈ **100초대** — YAML 몇 줄로 40% 단축. ✅ critical path가 integration(70)으로 바뀌었습니다 — **다음 최적화 대상은 integration이지 lint가 아닙니다**(lint를 0초로 만들어도 전체는 불변). 실전의 다음 수: integration 분할(05의 테스트 분할)·캐시(19)·affected(20).

## Step 4. flaky 탐지 — 같은 커밋, 다른 결과

```bash
cat > .github/workflows/flaky.yml <<'EOF'
name: flaky
on: [workflow_dispatch]
permissions: { contents: read }
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: 불안정한 테스트 (40% 실패 — 타이밍 의존 재현)
        run: |
          [ $((RANDOM % 10)) -lt 4 ] && { echo "FLAKY FAIL"; exit 1; } || echo "PASS"
EOF
git add -A && git commit -qm "flaky test" && git push -q

# 같은 커밋에서 6번 실행 (재시도 상황 재현)
for i in 1 2 3 4 5 6; do gh workflow run flaky; sleep 30; done
sleep 60
```

## Step 5. flaky 리포트 — 신호를 자동으로

```bash
gh api "repos/{owner}/{repo}/actions/runs?per_page=20" > runs2.json
python3 <<'EOF'
import json
from collections import defaultdict
runs = [r for r in json.load(open('runs2.json'))['workflow_runs']
        if r['name']=='flaky' and r['status']=='completed']

by_sha = defaultdict(list)
for r in runs: by_sha[r['head_sha'][:7]].append(r['conclusion'])

print("=== flaky 탐지 리포트 (theory §5) ===")
for sha, results in by_sha.items():
    kinds = set(results)
    verdict = "🚨 FLAKY (같은 코드, 다른 결과)" if len(kinds) > 1 else "안정"
    rate = results.count('failure')/len(results)
    print(f"{sha}: {results} → {verdict}  flake rate={rate:.0%}")
print()
print("운영 처방: flake rate > 0 인 대상 → quarantine + 소유팀 티켓 (05의 격리 시스템)")
print("금지 처방: retry: 2 로 덮기 — 통계에서 사라져 영원히 안 고쳐짐")
EOF
```

예상: 같은 SHA에 success와 failure가 섞임 → FLAKY 판정. ✅ **"같은 커밋, 다른 결과"가 가장 강한 flaky 신호**입니다 — 사람이 재시도 버튼을 누르는 대신, 이 리포트가 주간 배치(lab-01 Step 4)로 돌며 격리 후보를 자동 공급합니다.

## Step 6. 산출물 — 최적화·flaky 운영 카드

```markdown
# 빌드 시간 최적화 순서 (매번 이 순서)
1. 측정: 잡·스텝별 시간 (API/timing)
2. 그래프: needs 화살표 — "가짜 의존" 제거가 공짜 최적화 (Step 3: 40%)
3. critical path 위의 최대 항목 하나: 캐시(19) / 분할(05) / affected(20) / 러너(08)
4. 다시 측정 — 경로가 바뀌었는가요? (바뀐 경로의 최대 항목으로)

# flaky 운영 루프 (주간)
- 자동 탐지: 같은 SHA 교차 결과 + 테스트 단위 flake rate
- quarantine + 소유팀 + 2주 시한 (수정 또는 삭제 — 05)
- 대시보드: "재시도로 성공한 런 %" — 커지면 신뢰 붕괴 진행 중
```

## 정리

```bash
bash cleanup.sh
```
