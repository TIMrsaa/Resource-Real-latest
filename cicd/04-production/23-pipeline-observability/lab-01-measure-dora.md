# Lab 01 — 워크플로 이력에서 숫자 뽑기: duration, queue, DORA

"느낌"을 API 데이터로 바꿉니다 — 실행 이력을 만들고, 그 이력에서 파이프라인 지표와 DORA를 계산합니다.

전제: gh CLI, python3.

## Step 1. 이력 생성 — 성공·실패·배포가 섞인 저장소

```bash
mkdir -p ~/ci-lab/observ/.github/workflows && cd ~/ci-lab/observ
git init -q . && git config user.email l@e.com && git config user.name L

cat > .github/workflows/ci.yml <<'EOF'
name: ci
on: [push]
permissions: { contents: read }
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: 테스트 (일부러 가끔 실패)
        run: |
          sleep $((RANDOM % 20 + 10))
          [ ! -f fail.flag ] || exit 1
EOF
cat > .github/workflows/deploy.yml <<'EOF'
name: deploy
on: { push: { branches: [main] } }
permissions: { contents: read }
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "deploying $(git rev-parse --short HEAD)" && sleep 5
EOF

git add -A && git commit -qm "init"
gh repo create cicd-lab-observ --public --source=. --push >/dev/null

# 이력 만들기: 성공 5 + 실패 2 (커밋 시각이 리드타임의 시작점이 됩니다)
for i in 1 2 3; do echo $i > f.txt; git add -A; git commit -qm "change $i"; git push -q; sleep 45; done
touch fail.flag && git add -A && git commit -qm "bad change" && git push -q && sleep 45
git rm -q fail.flag && git commit -qm "fix: revert bad change" && git push -q && sleep 45
for i in 4 5; do echo $i > f.txt; git add -A; git commit -qm "change $i"; git push -q; sleep 45; done
```

## Step 2. 파이프라인 계층 — duration·queue·성공률

```bash
gh api "repos/{owner}/{repo}/actions/runs?per_page=50" > runs.json

python3 <<'EOF'
import json
from datetime import datetime
P = lambda s: datetime.fromisoformat(s.replace('Z','+00:00'))
runs = [r for r in json.load(open('runs.json'))['workflow_runs'] if r['status']=='completed']

ci = [r for r in runs if r['name']=='ci']
dur   = sorted((P(r['updated_at'])-P(r['run_started_at'])).total_seconds() for r in ci)
queue = sorted((P(r['run_started_at'])-P(r['created_at'])).total_seconds() for r in ci)
ok    = sum(1 for r in ci if r['conclusion']=='success')

pct = lambda a,p: a[min(len(a)-1, int(len(a)*p))] if a else 0
print(f"=== 파이프라인 계층 (ci, {len(ci)}런) ===")
print(f"duration   p50={pct(dur,.5):.0f}s  p90={pct(dur,.9):.0f}s")
print(f"queue time p50={pct(queue,.5):.0f}s  p90={pct(queue,.9):.0f}s   ← 러너 부족의 선행 지표(eks 13)")
print(f"성공률     {ok}/{len(ci)} = {ok/len(ci)*100:.0f}%")
EOF
```

예상: duration p50/p90, queue(호스티드 러너는 보통 수 초 — self-hosted에서 이 값이 자라면 증설 신호), 성공률 ~71%. ✅ "요즘 CI 어때?"가 세 개의 숫자가 됐습니다 — 주간 추이로 만들면 팀의 결정(러너·캐시)이 데이터를 갖습니다.

## Step 3. DORA 계층 — 빈도·리드타임·실패율

```bash
git fetch -q origin main
python3 <<'EOF'
import json, subprocess
from datetime import datetime
P = lambda s: datetime.fromisoformat(s.replace('Z','+00:00'))
runs = [r for r in json.load(open('runs.json'))['workflow_runs'] if r['status']=='completed']
dep = sorted([r for r in runs if r['name']=='deploy' and r['conclusion']=='success'],
             key=lambda r: r['run_started_at'])

print("=== DORA (측정 정의를 코드로 고정 — theory §2) ===")
# ① 배포 빈도 = 성공한 deploy 런 수 / 기간
span_h = (P(dep[-1]['updated_at']) - P(dep[0]['created_at'])).total_seconds()/3600 or 1
print(f"배포 빈도: {len(dep)}회 / {span_h:.1f}h")

# ② 리드타임 = 커밋 시각 → 그 커밋의 배포 완료 시각
leads = []
for r in dep:
    t = subprocess.run(['git','show','-s','--format=%cI', r['head_sha']],
                       capture_output=True, text=True).stdout.strip()
    if t: leads.append((P(r['updated_at']) - datetime.fromisoformat(t)).total_seconds())
leads.sort()
if leads: print(f"리드타임: p50={leads[len(leads)//2]:.0f}s (커밋→prod 도달)")

# ③ 변경 실패율 (근사): 배포 후 'fix:'/'revert' 커밋이 뒤따른 배포 비율
msgs = [subprocess.run(['git','show','-s','--format=%s', r['head_sha']],
        capture_output=True, text=True).stdout.strip() for r in dep]
fails = sum(1 for i,m in enumerate(msgs[:-1]) if 'fix' in msgs[i+1] or 'revert' in msgs[i+1].lower())
print(f"변경 실패율(근사): {fails}/{len(dep)-1} — 배포 다음이 수정 커밋인 비율")
print("④ MTTR: 장애 시스템(사고 티켓)과 결합 필요 — 파이프라인 데이터만으로는 불완전")
EOF
```

예상: 빈도·리드타임 p50·실패율(bad change → fix가 1건 잡힘). ✅ 핵심은 값이 아니라 **정의가 코드로 고정**됐다는 것 — "리드타임이 뭐냐"는 논쟁이 스크립트 리뷰로 바뀝니다. 실습 데이터의 리드타임은 분 단위지만, 실조직에서 이 값은 대개 **일 단위**입니다 — 파이프라인이 아니라 리뷰 대기·승인이 지배하기 때문(3계층의 통찰).

## Step 4. 주기 배치로 자동화 — 스케줄 워크플로

```bash
cat > .github/workflows/metrics.yml <<'EOF'
name: weekly-metrics
on:
  schedule: [{ cron: '0 0 * * 1' }]     # 매주 월요일
  workflow_dispatch:
permissions: { contents: read, actions: read }
jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: 지난주 지표 집계
        run: |
          gh api "repos/${{ github.repository }}/actions/runs?per_page=100" \
            --jq '[.workflow_runs[] | select(.status=="completed")] |
                  "runs=\(length) success=\([.[]|select(.conclusion=="success")]|length)"'
        env: { GH_TOKEN: "${{ secrets.GITHUB_TOKEN }}" }
      # 실전: 집계 결과를 대시보드 저장소/메트릭 시스템으로 push (eks 12의 파이프라인과 합류)
EOF
git add -A && git commit -qm "ci: weekly metrics batch" && git push -q
gh workflow run weekly-metrics >/dev/null 2>&1 && echo "배치 트리거됨"
```

✅ theory §6의 "작게 시작": 스케줄 배치 → 대시보드. 실시간 계측(OTel)은 이 배치가 답 못 하는 질문이 생길 때.

## Step 5. 산출물 — 파이프라인 SLO 초안

```markdown
# 파이프라인 SLO (팀 계층 — 주간 리뷰)
- ci duration p90 ≤ 10분        (어기면: critical path 분석 — lab-02)
- queue time p90 ≤ 30초         (어기면: 러너 증설 검토 — 08, L=λW로 산정)
- main 성공률 ≥ 95%             (어기면: 실패 원인 분류 — 코드/flaky/인프라)
- 재시도로 성공한 런 ≤ 5%       (어기면: flaky 사냥 — lab-02)
★ 서비스 SLO(eks 12)와 같은 형식 — 파이프라인도 프로덕션이므로
```

## 정리

저장소는 lab-02에서 계속 사용. 유지.
