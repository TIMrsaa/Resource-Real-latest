# Lab 01 — 런타임 카테고리 전수 조사와 층 분류

landscape의 런타임 칸을 뽑아 "층"(CRI/OCI/격리 변주/Wasm)으로 분류합니다 — 로고 벽을 구조로 바꾸는 연습.

전제: 01 lab-01의 landscape.yml.

## Step 1. 컨테이너 런타임 서브카테고리 전수

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
for cat in data['landscape']:
    if 'Runtime' not in cat['name']: continue
    for sub in cat.get('subcategories', []):
        items = sub.get('items', [])
        print(f"\n=== {cat['name']} / {sub['name']} — {len(items)}개 ===")
        for it in sorted(items, key=lambda x: x['name'].lower()):
            print(f"{it.get('project','·'):12s} {it['name']}")
EOF
```

예상: Container Runtime 서브카테고리에 containerd(graduated), CRI-O(graduated), Kata, gVisor, WasmEdge... + 비프로젝트들. (Runtime 대분류에는 스토리지·네트워킹 서브카테고리도 있습니다 — 각각 05·04의 영토입니다.)

## Step 2. 층 분류 — 이 카테고리 읽기의 핵심 기술

```bash
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
layers = {
  'CRI 레벨 (kubelet의 대화 상대)': ['containerd','cri-o'],
  'OCI 레벨 — 표준 격리':          ['runc','crun','youki'],
  'OCI 레벨 — 강화 격리':          ['gvisor','kata','firecracker'],
  'Wasm (다른 실행 모델)':         ['wasmedge','wasmtime','wasmcloud','spin'],
}
idx = {}
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        for it in sub.get('items', []):
            idx[it['name'].lower()] = it.get('project','·')
print("=== 층 분류표 (theory §1·§3) ===")
for layer, keys in layers.items():
    print(f"\n[{layer}]")
    for k in keys:
        hit = [(n,m) for n,m in idx.items() if k in n]
        for n,m in hit[:1]: print(f"  {m:12s} {n}")
        if not hit: print(f"  (landscape 밖) {k} — OCI/외부 재단 소속일 수 있음 (runc=OCI, Kata=OpenInfra)")
print("\n→ 같은 칸의 로고라도 층이 다르면 경쟁자가 아닙니다 — 이 표가 채택 회의의 첫 슬라이드")
EOF
```

✅ **runc·Kata·Firecracker가 landscape에 없거나 배지가 없는 이유** 자체가 학습 포인트입니다 — CNCF만이 재단이 아닙니다(runc=OCI/LF, Kata=OpenInfra, Firecracker=AWS 오픈소스). 지도는 CNCF 중심일 뿐 생태계 전체가 아닙니다.

## Step 3. 건강검진 1건 — 스펙트럼 오른쪽에서

```bash
# 강화 격리를 검토한다고 가정 — gVisor의 활동성
R="google/gvisor"
gh api "repos/$R/releases?per_page=3" --jq '.[] | "\(.tag_name)  \(.published_at)"' 2>/dev/null || \
  gh api "repos/$R/tags?per_page=3" --jq '.[].name'
gh api "repos/$R/commits?per_page=1" --jq '.[0].commit.committer.date'
echo "→ 단일 벤더(Google) 오픈소스 — 01의 소견서에서 '유지보수자 다양성' 항목이 어떻게 평가될지 생각해보라"
echo "   (재단 프로젝트가 아니어도 훌륭할 수 있습니다 — 단, 리스크 축이 다르다는 것을 명시하고 채택)"
EOF
```

## Step 4. 산출물

```markdown
# 런타임 카테고리 — 조사 결과 (조사일: ____)
- CRI 레벨 후보: containerd / CRI-O — 우리 플랫폼의 기본값: ___
- 강화 격리 필요 워크로드: 있음/없음 — 있다면 스펙트럼 어느 지점: ___
- Wasm 관찰 대상: ___ (채택 아님 — 추세 관찰 목록)
- 재단 밖 구성원 확인: runc(OCI), Kata(OpenInfra), Firecracker(AWS) — CNCF 지도의 경계 인지
```

## 정리

landscape.yml 유지.
