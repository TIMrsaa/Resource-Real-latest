# Lab 01 — 스토리지 전수 조사: 역할 분류가 첫 기술

landscape의 스토리지 칸을 뽑아 "시스템/오케스트레이터/K8s 네이티브/백업/드라이버"로 가릅니다.

전제: 01 lab-01의 landscape.yml.

## Step 1. 스토리지 서브카테고리 전수

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        if 'storage' not in sub['name'].lower(): continue
        items = sub.get('items', [])
        cncf = [i for i in items if i.get('project')]
        print(f"=== {cat['name']} / {sub['name']} — {len(items)}개 (CNCF {len(cncf)}) ===")
        for it in sorted(cncf, key=lambda x: x['name'].lower()):
            print(f"{it['project']:12s} {it['name']}")
EOF
```

예상: Rook(graduated), CubeFS, Longhorn, OpenEBS, Piraeus 등 + 다수의 비프로젝트 상용(각종 스토리지 벤더 — 이 칸은 특히 상용 로고가 많습니다).

## Step 2. 역할 분류 — Rook 함정 통과 의례

```bash
python3 <<'EOF'
roles = {
  '오케스트레이터 (저장 안 함!)': [('Rook','Ceph 오퍼레이터 — 평가는 Ceph+Rook 세트')],
  'K8s 네이티브 시스템':          [('Longhorn','분산 블록·레플리카'),('OpenEBS','CAS 스펙트럼'),('TopoLVM','로컬 LVM')],
  '대형 시스템 (K8s 밖 출신)':    [('Ceph','블록+파일+오브젝트 — 운영 무게급'),('CubeFS','분산 파일+오브젝트'),('MinIO','S3 호환 — 비CNCF·AGPL ⚠️')],
  '백업·이동':                    [('Velero','리소스+볼륨 백업 — k8s 36')],
  '클라우드 드라이버':            [('EBS/EFS CSI','시스템은 클라우드가 운영 — 실무 기본값')],
}
for role, items in roles.items():
    print(f"\n[{role}]")
    for n, d in items: print(f"  {n:12s} {d}")
print("\n→ 같은 칸의 로고라도 역할이 다르면 비교 불가 — 'Rook vs Longhorn'은 절반만 성립")
print("  (Rook-Ceph vs Longhorn 이면 성립 — 시스템까지 명시해야 비교가 됩니다)")
EOF
```

✅ **"Rook vs Longhorn"을 "Rook-Ceph vs Longhorn"으로 고쳐 말하는 것** — 이 카테고리 문해력의 리트머스.

## Step 3. 건강검진 — 데이터를 맡길 곳이므로 두 배로

```bash
# 데이터 중력 때문에 이 카테고리의 소견서는 가장 무겁습니다 — Longhorn으로 연습
R="longhorn/longhorn"
gh api "repos/$R/releases?per_page=5" --jq '.[] | "\(.tag_name)  \(.published_at)"'
gh api "repos/$R/contents" --jq '.[].name' | grep -iE "governance|maintainers|adopters" || echo "(루트에 없음 — 조직 저장소 확인)"
echo "→ 추가로 반드시: 업그레이드 경로 문서의 품질, 데이터 마이그레이션 도구,"
echo "   과거 데이터 손실 이슈의 사후 보고 품질 (스토리지 특화 검진 항목)"
```

✅ 스토리지 소견서에는 01의 5종에 **+3**(업그레이드 경로, 마이그레이션 도구, 손실 사고 대응 이력)을 붙입니다.

## Step 4. 산출물

```markdown
# 스토리지 지도 — 조사 결과 (조사일: ____)
- 우리 현재 구성: 블록 ___ / 파일 ___ / 오브젝트 ___ / 백업 ___
- 관리형 의존 지점과 자체 운영 검토 트리거(§4 조건): ___
- Rook 함정 통과: "시스템 vs 오케스트레이터" 구분을 팀 용어로 정착
- 검진 소견(+스토리지 특화 3항목): ___
```

## 정리

landscape.yml 유지.
