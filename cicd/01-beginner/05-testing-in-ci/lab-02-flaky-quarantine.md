# Lab 02 — flaky를 재실행하지 말고 격리하세요

01에서 "게이트의 신뢰"가 자동 배포의 전제라고 했습니다. flaky 테스트는 그 신뢰를 죽입니다 — 그런데 대부분의 팀은 재실행 버튼으로 대응합니다. 이 랩은 **탐지 → 격리 → 추적**의 시스템을 만듭니다.

## Step 1. flaky를 심습니다 (다섯 원천 중 셋)

```bash
cd ~/ci-lab/testing
cat > tests/test_flaky.py <<'EOF'
import random, time, os
import pytest

# ① 시간 의존 — 실행이 느린 러너에서 실패합니다
def test_time_dependent():
    start = time.time()
    time.sleep(0.05)
    assert time.time() - start < 0.06        # 러너가 바쁘면 실패

# ② 순서 의존 — 공유 상태
_cache = []
def test_appends():
    _cache.append(1)
    assert len(_cache) == 1                  # 다른 테스트가 먼저 돌면 실패

def test_also_appends():
    _cache.append(2)
    assert len(_cache) <= 2

# ③ 진짜 비결정성 — 20% 확률로 실패
def test_random_failure():
    assert random.random() > 0.2
EOF

pip install -q pytest-randomly 2>/dev/null || true
```

## Step 2. 탐지 — 같은 커밋을 반복 실행하면 진실이 드러납니다

```bash
echo "=== 10회 반복: 결과가 갈리면 flaky ==="
for i in $(seq 1 10); do
  python -m pytest -q tests/test_flaky.py -p no:randomly 2>&1 | tail -1
done | sort | uniq -c
```

예상: `passed`와 `failed`가 **섞여 나옵니다**. 한 번의 실행 결과는 정보가 아니었던 것입니다.

순서 의존을 드러내려면 랜덤 순서로:

```bash
echo "=== 랜덤 순서 5회 ==="
for i in $(seq 1 5); do
  python -m pytest -q tests/test_flaky.py 2>&1 | tail -1     # pytest-randomly가 순서를 섞습니다
done
```

✅ **`pytest-randomly`(또는 `go test -shuffle=on`)는 순서 의존을 상시 노출시키는 장치**입니다. 기본으로 켜두면 flaky가 나중이 아니라 지금 발견됩니다.

## Step 3. 격리 마커 — 게이트에서 빼되 눈에는 보이게

```bash
cat > pytest.ini <<'EOF'
[pytest]
markers =
    quarantine: 불안정으로 격리됨 — 필수 게이트에서 제외, 별도 잡에서 추이 관찰
addopts = --strict-markers
EOF

# 격리 대상에 마커를 답니다 (이슈 번호와 기한을 반드시 함께!)
python - <<'PY'
import re, pathlib
p = pathlib.Path("tests/test_flaky.py")
s = p.read_text()
s = s.replace(
    "def test_random_failure():",
    '@pytest.mark.quarantine  # flaky: #123 (담당 alice, 만료 2026-08-15)\ndef test_random_failure():')
p.write_text(s)
PY

echo "--- 게이트용 실행 (격리 제외) ---"
python -m pytest -q -p no:randomly -m "not quarantine" tests/test_flaky.py 2>&1 | tail -1
echo "--- 격리 잡 (관찰용, 실패해도 게이트 무관) ---"
python -m pytest -q -p no:randomly -m "quarantine" tests/test_flaky.py 2>&1 | tail -1
```

✅ 핵심 차이: **재실행은 그 테스트가 계속 게이트에 있으면서 아무것도 검증하지 않게** 만듭니다. 격리는 게이트에서 빼되 **여전히 돌려서 상태를 관찰**하고, 기한 내 고치거나 삭제하게 합니다.

## Step 4. CI에 격리 시스템 심기

```bash
cat > .github/workflows/test.yml <<'EOF'
name: test
on: [push, pull_request]
permissions: { contents: read, issues: write }

jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12", cache: pip }
      - run: pip install -r requirements-dev.txt
      - name: 게이트 — 격리된 것 제외, 순서 랜덤
        run: pytest -q -m "not quarantine" tests/

  quarantined:                       # 격리된 테스트를 계속 관찰 (실패해도 게이트 무관)
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12", cache: pip }
      - run: pip install -r requirements-dev.txt
      - run: pytest -q -m quarantine tests/ || echo "격리 테스트 여전히 불안정"

  ci:
    if: always()
    needs: [unit]                    # ★ quarantined는 needs에 없다 = 게이트가 아닙니다
    runs-on: ubuntu-latest
    steps:
      - run: '[ "${{ needs.unit.result }}" = "success" ]'
EOF

cat > .github/workflows/flaky-detect.yml <<'EOF'
name: flaky-detect
on:
  schedule: [{ cron: "0 18 * * *" }]      # 야간 (theory §6의 배치)
  workflow_dispatch:
permissions: { contents: read, issues: write }

jobs:
  detect:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12", cache: pip }
      - run: pip install -r requirements-dev.txt

      - name: 같은 커밋을 10회 — 결과가 갈리는 테스트 색출
        id: detect
        run: |
          fails=0
          for i in $(seq 1 10); do
            pytest -q -m "not quarantine" tests/ >/dev/null 2>&1 || fails=$((fails+1))
          done
          echo "fails=$fails" >> "$GITHUB_OUTPUT"
          echo "10회 중 $fails회 실패"

      - name: flaky 발견 시 이슈 생성 (추적 — 무시가 아닙니다)
        if: steps.detect.outputs.fails != '0' && steps.detect.outputs.fails != '10'
        env: { GH_TOKEN: "${{ github.token }}" }
        run: |
          gh issue create \
            --title "flaky 탐지: 10회 중 ${{ steps.detect.outputs.fails }}회 실패" \
            --body "같은 커밋(${GITHUB_SHA::8})에서 결과가 갈립니다. 격리(@pytest.mark.quarantine) 후 원인 조사 필요. 원천 체크: 시간/순서/동시성/외부의존/자원" \
            --label flaky
EOF
```

읽는 법: `fails`가 0이면 안정, 10이면 **진짜 실패**(회귀), 그 사이면 **flaky**. 이 삼분법이 자동 탐지의 핵심 논리입니다.

```bash
echo "pytest-randomly==3.16.0" >> requirements-dev.txt
git add -A && git commit -qm "test: quarantine system + flaky detection" && git push -q
sleep 60; gh run list --limit 2
```

## Step 5. 커버리지를 올바르게 — diff 커버리지

```bash
pip install -q pytest-cov diff-cover 2>/dev/null || true

python -m pytest -q -m "not quarantine" --cov=app --cov-report=xml tests/ >/dev/null 2>&1
echo "--- 전체 커버리지 (참고용, 목표 아님) ---"
python -c "
import xml.etree.ElementTree as ET
r = ET.parse('coverage.xml').getroot()
print(f\"line-rate: {float(r.get('line-rate'))*100:.1f}%\")"

echo "--- diff 커버리지: 이 변경이 검증됐는가 (진짜 질문) ---"
diff-cover coverage.xml --compare-branch=main 2>/dev/null | head -8 || echo "(main과 diff 없음 — PR에서 의미가 생깁니다)"
```

✅ **전체 80%는 목표가 되는 순간 굿하트의 함정**입니다(theory §5). PR에서 물어야 할 것은 "당신이 바꾼 줄이 테스트를 지나갔는가"다.

## Step 6. 산출물 — 테스트 정책 문서

```markdown
# 테스트 정책 v1
## 피라미드 목표 비율
- 단위 70% / 통합 20% / e2e 10%. e2e는 핵심 사용자 여정 3~5개만
- 아이스크림 콘 징후(e2e 과입니다)는 **설계 부채 신호** — 의존성 주입 리팩터링 백로그로

## 더블
- Fake 우선(행동 검증). Mock은 "호출 계약 자체가 명세"일 때만
- 외부 세계(DB/네트워크/시계/커널)는 인터페이스 뒤로 — eks 28·29의 그 사상

## flaky
- 재실행 금지. 발견 즉시 @quarantine + 이슈 + **담당자 + 만료일**
- 격리는 게이트 제외이지 무시가 아닙니다: 별도 잡에서 계속 실행
- 만료일까지 미해결 → 삭제(썩은 테스트는 부채)
- 상시 랜덤 순서 실행(pytest-randomly / go test -shuffle=on)
- 야간 반복 탐지: 10회 중 1~9회 실패 = flaky → 자동 이슈

## 커버리지
- 게이트: **diff 커버리지** (변경된 줄) — 절대 목표치 금지
- 추세 하락 시 경고. 위험 도메인(결제·인증) 0% 구간은 백로그

## CI 배치
- PR: lint ‖ 단위 ‖ 타입 → 통합. 목표 10분, 실패 피드백 1분
- main: + e2e(핵심 여정)
- 야간: 전체 e2e + flaky 탐지 + 의존성 스캔
```

## Step 7. 초급 트랙 졸업 점검

```markdown
01 → 파이프라인의 목적과 DORA 좌표계        [ ]
02 → 브랜치 전략은 릴리스 모델의 함수        [ ]
03 → Actions 실행 모델과 게이트 구현         [ ]
04 → 불변 아티팩트(캐시·멀티스테이지·다이제스트) [ ]
05 → 그 게이트를 **믿을 수 있게** 만드는 테스트  [ ]
→ 중급(06~13)에서: 재사용 워크플로, OIDC(장기 키 제거!), self-hosted 러너, AWS Code 시리즈
```

## 정리

```bash
bash cleanup.sh
```
