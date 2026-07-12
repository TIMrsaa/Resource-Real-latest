# Lab 01 — 카테고리 전수 조사: 데이터에서 분류표까지

01에서 만든 landscape.yml 파이프라인으로 이 카테고리의 전 항목을 뽑고, theory의 분류(배치/멀티클러스터/엣지/확장/대안)에 직접 배치합니다.

전제: 01 lab-01 완료(~/cncf-lab/landscape/landscape.yml).

## Step 1. 카테고리 항목 전수 추출

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
for cat in data['landscape']:
    if 'Orchestration' not in cat['name']: continue
    for sub in cat.get('subcategories', []):
        if 'Scheduling' not in sub['name']: continue
        items = sub.get('items', [])
        print(f"=== {cat['name']} / {sub['name']} — {len(items)}개 ===")
        for it in sorted(items, key=lambda x: x['name'].lower()):
            m = it.get('project', '·')          # · = CNCF 프로젝트 아님
            print(f"{m:12s} {it['name']}")
EOF
```

예상: Kubernetes(graduated)부터 상용 제품(·)까지 수십 항목. ✅ 화면의 로고 벽이 **분류 가능한 목록**이 됐습니다 — 01의 규율(로고≠프로젝트)이 여기서도 첫 필터입니다.

## Step 2. theory의 분류로 재배치 — 지도에 내 손으로 핀 꽂기

```bash
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
buckets = {
  '배치/큐잉':      ['volcano','kueue','yunikorn','armada'],
  '멀티클러스터':   ['karmada','open cluster management','clusternet','fleet','cluster api'],
  '엣지':           ['kubeedge','k3s','openyurt','superedge','akri'],
  '워크로드 확장':  ['openkruise'],
  'K8s 대안/레거시':['nomad','docker swarm','mesos'],
}
names = []
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        for it in sub.get('items', []):
            names.append((it['name'], it.get('project','·')))

print("=== theory 분류 → landscape 대조 ===")
for bucket, keys in buckets.items():
    print(f"\n[{bucket}]")
    for k in keys:
        hits = [(n,m) for n,m in names if k in n.lower()]
        for n,m in hits[:2]: print(f"  {m:12s} {n}")
        if not hits: print(f"  (미발견)     {k} — 이름 변경/졸업/아카이브? 직접 검색")
print("\n→ '미발견'과 '분류 밖 신규 항목'이 지도의 변동분 — 이것을 쫓는 것이 지도 유지법")
EOF
```

✅ theory의 표는 **어제의 지도**입니다 — 이 스크립트가 오늘과의 diff를 보여줍니다. 분류에 안 잡히는 새 이름이 보이면 그 프로젝트의 README를 열어 어느 버킷인지(또는 새 버킷인지) 판정해보세요 — 그 판정 행위가 지도 읽기 근육입니다.

## Step 3. 성숙도 재검증 — theory 표기와의 대조

```bash
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
watch = ['Volcano','Karmada','KubeEdge','OpenKruise','Kueue','K3s','Nomad']
idx = {}
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        for it in sub.get('items', []):
            idx[it['name'].lower()] = it.get('project', 'CNCF 프로젝트 아님')
for w in watch:
    print(f"{w:14s} → {idx.get(w.lower(), 'landscape에 없음(서브카테고리 다름? 전체 검색 필요)')}")
EOF
```

✅ theory의 "성숙도급*" 표기를 **오늘 데이터**로 확정 — 다르면 theory가 아니라 데이터가 맞습니다(그리고 그 발견을 기록해두면 45·48에서 씁니다).

## Step 4. 건강검진 1건 — 01의 소견서 재사용

```bash
# 이 카테고리에서 채택을 고민할 법한 것 하나 (예: Karmada)로 01 lab-02의 5종 검사
R="karmada-io/karmada"
gh api "repos/$R/releases?per_page=3" --jq '.[] | "\(.tag_name)  \(.published_at)"'
gh api "repos/$R/contents" --jq '.[].name' | grep -iE "adopters|governance|maintainers" || true
gh api "repos/$R/contributors?per_page=5" --jq '.[].login'
```

✅ 01의 소견서 양식에 기입 — 지도 모듈마다 최소 1건씩 이 근육을 씁니다.

## Step 5. 산출물 — 이 카테고리의 내 지도

```markdown
# 스케줄링&오케스트레이션 — 조사 결과 (조사일: ____)
- landscape 항목 수: ___ / CNCF 프로젝트: ___
- theory 대비 변동: (승격/신규/소멸) ___
- 우리 환경에서 실제 후보가 되는 버킷: ___ (증상 → 처방 표 — theory §4 기준)
- 건강검진 소견: <프로젝트> 🟢🟡🔴 ___
```

## 정리

landscape.yml 유지 (다음 지도 모듈들 공용).
