# Lab 02 — 졸업 심사 실물 읽기와 심사관의 눈 훈련

TOC의 실제 실사(due diligence) 문서를 읽고, 프로젝트 하나를 골라 건강도 5종 검사를 직접 수행합니다.

전제: gh CLI, lab-01의 landscape.yml.

## Step 1. 심사 기준의 원문 — TOC 저장소

```bash
cd ~/cncf-lab/landscape
gh repo clone cncf/toc ~/cncf-lab/toc -- --depth 20 2>/dev/null || \
  git clone --depth 20 https://github.com/cncf/toc.git ~/cncf-lab/toc

ls ~/cncf-lab/toc/process/ | head -10
grep -rn "graduation" ~/cncf-lab/toc/process/*.md -il | head -5
```

졸업 기준 문서를 열어 핵심 항목을 확인하세요 — 다회사 유지보수자(committers from at least two organizations), 보안 프로세스, 실명 채택(adopters), 거버넌스 문서. ✅ theory §3의 표가 **원문 그대로** 존재함을 확인 — 인용할 때는 이 원문이 출처입니다.

## Step 2. 실사의 실물 — 최근 졸업 프로젝트의 서류

```bash
# 졸업 관련 이슈/PR 검색 (TOC 저장소에서 심사가 공개로 진행됩니다!)
gh issue list -R cncf/toc --state all --search "graduation" --limit 10 \
  --json number,title,state --jq '.[] | "\(.number)  [\(.state)]  \(.title)"'
```

최근 졸업 건 하나를 골라 열어보고, 심사 과정을 관찰하세요:

```markdown
# 실사 문서에서 찾을 것 (읽으며 체크)
- [ ] 채택 인터뷰: 실사용 기업들의 실명 증언 (End User Community — theory §1)
- [ ] 유지보수자 분포: 어느 회사들에서 몇 명 (단일 벤더 탈피 증명)
- [ ] 보안 감사 링크: 제3자 감사 보고서 + 지적 사항의 수정 이력
- [ ] TAG 리뷰: 해당 분야 TAG의 기술 평가
- [ ] TOC 투표: 공개 투표 기록
★ 전 과정이 공개 저장소의 이슈·PR — "밀실 심사가 아니다"가 신뢰의 근거
```

✅ 승격이 마케팅이 아니라 **공개 문서 절차**임을 실물로 확인 — cicd 27의 proposal, 28의 TEP와 같은 문화의 재단 스케일판.

## Step 3. 심사관의 눈 훈련 — 프로젝트 하나 건강검진

Incubating이나 Sandbox에서 하나를 골라(예: 요즘 관심 있는 것) 5종 검사를 직접:

```bash
PROJ_REPO="<org/repo — 직접 선택>"   # 예: 관심 프로젝트의 GitHub 저장소

# ① 유지보수자 다양성 (근사: 최근 커밋 상위 기여자의 소속)
gh api "repos/$PROJ_REPO/contributors?per_page=10" --jq '.[].login' | head -10
echo "→ 상위 기여자들의 소속 회사를 프로필·커밋 이메일로 확인 — 한 회사가 80%면 버스 팩터 경고"

# ② 릴리스 리듬
gh api "repos/$PROJ_REPO/releases?per_page=5" --jq '.[] | "\(.tag_name)  \(.published_at)"'
echo "→ 간격이 규칙적인가요? 마지막 릴리스가 언제인가요? (1년 침묵 = kaniko 신호)"

# ③ 채택의 실명성
gh api "repos/$PROJ_REPO/contents" --jq '.[].name' | grep -iE "adopters|users" || echo "ADOPTERS 파일 없음 ⚠️"

# ④ 거버넌스의 실재
gh api "repos/$PROJ_REPO/contents" --jq '.[].name' | grep -iE "governance|maintainers|owners" || echo "거버넌스 문서 없음 ⚠️"

# ⑤ 이슈 응답성 (근사: 최근 이슈에 유지보수자 응답이 달리는가)
gh issue list -R "$PROJ_REPO" --limit 5 --json number,comments --jq '.[] | "\(.number)  댓글:\(.comments)"'
```

## Step 4. DevStats — 추세를 봅니다

```bash
cat <<'EOF'
https://devstats.cncf.io 에서 방금 그 프로젝트의 대시보드를 열고:
  - Contributors 추이 (늘고 있나, 정점 찍고 하락 중인가 — 절대값보다 방향)
  - Companies contributing (다양성의 시계열 — ①의 추세판)
  - New PRs / PR 처리 시간 (커뮤니티가 살아 있는가)
★ 스냅샷(오늘의 스타 수)이 아니라 추세가 지속성의 예측 변수입니다
EOF
```

## Step 5. 판정 연습 — 한 장짜리 소견서

```markdown
# 프로젝트 건강 소견서: <프로젝트명> (검사일: ____)
| 항목 | 관찰 | 판정 |
|------|------|------|
| 유지보수자 다양성 | 상위 10명 중 __개 회사 | 🟢/🟡/🔴 |
| 릴리스 리듬 | 최근 5릴리스 간격 __ | 🟢/🟡/🔴 |
| 채택 실명성 | ADOPTERS __개 실명 | 🟢/🟡/🔴 |
| 거버넌스 실재 | 문서 + 작동 흔적 | 🟢/🟡/🔴 |
| 활동 추세 | DevStats 방향 | 🟢/🟡/🔴 |
종합: 프로덕션 채택 관점 __ / 기여 대상 관점 __
근거 한 줄: ______
```

✅ 이 소견서 양식이 Part 4 전체에서 재사용됩니다 — 심층 모듈(11~)마다 그 프로젝트의 소견서를 갱신하고, 48(비교 가이드)에서 카테고리 내 선택의 근거가 됩니다.

## Step 6. 반대편 훈련 — 아카이브에서 배우기

```bash
cat <<'EOF'
https://www.cncf.io/archived-projects/ 에서 아카이브 2~3개를 골라:
  - 왜 아카이브됐나 (TOC 이슈에 논의가 남아 있습니다)
  - 죽기 전 신호는 무엇이었나 (Step 3의 5종 중 무엇이 먼저 꺼졌나)
  - 사용자들은 어디로 이주했나 (rkt→containerd/CRI-O처럼)
★ 부검이 건강검진 실력을 만듭니다 — 다음에 살아있는 프로젝트에서 같은 신호를 봅니다
EOF
```

## 정리

```bash
bash cleanup.sh
```
