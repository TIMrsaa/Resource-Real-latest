# Lab 01 — landscape를 데이터로: 지도를 직접 집계합니다

landscape.cncf.io의 화면 뒤에 있는 원본(landscape.yml)을 받아, 카테고리·성숙도 분포를 스스로 집계합니다 — 읽는 시점이 언제든 유효한 방법을 익힙니다.

전제: python3(pyyaml), git 또는 curl.

## Step 1. 원본 데이터 확보

```bash
mkdir -p ~/cncf-lab/landscape && cd ~/cncf-lab/landscape
curl -sL https://raw.githubusercontent.com/cncf/landscape/master/landscape.yml -o landscape.yml
python3 -c "import yaml" 2>/dev/null || pip3 install pyyaml --quiet
wc -l landscape.yml            # 수만 줄 — 화면의 로고 하나하나가 이 안의 항목
```

## Step 2. 지도의 뼈대 — 카테고리 축 추출

```bash
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
print("=== 카테고리(대분류) / 서브카테고리 ===")
for cat in data['landscape']:
    subs = [s['name'] for s in cat.get('subcategories', [])]
    total = sum(len(s.get('items', [])) for s in cat.get('subcategories', []))
    print(f"\n{cat['name']}  ({total}개 항목)")
    for s in subs: print(f"   - {s}")
EOF
```

예상: Provisioning / Runtime / Orchestration & Management / App Definition & Development / Observability & Analysis 등 대분류와 그 아래 서브카테고리(Scheduling & Orchestration, Container Runtime, Service Mesh, ...). ✅ **02~10 지도 모듈들이 따라갈 축**이 이 구조입니다.

## Step 3. 핵심 구분 — CNCF 프로젝트 vs 그냥 실린 것

```bash
python3 <<'EOF'
import yaml
from collections import Counter
data = yaml.safe_load(open('landscape.yml'))
maturity = Counter(); total = 0
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        for item in sub.get('items', []):
            total += 1
            p = item.get('project')          # 이 키가 있어야 CNCF 프로젝트!
            if p: maturity[p] += 1
print(f"landscape 전체 항목: {total}")
print(f"그중 CNCF 프로젝트: {sum(maturity.values())}  ← 나머지는 회원사 제품 등")
for level, n in maturity.most_common():
    print(f"  {level:12s} {n}")
EOF
```

예상: 전체 수천 항목 중 CNCF 프로젝트는 200개 안팎, graduated ~35 / incubating / sandbox 분포. ✅ theory §5의 규율을 데이터로 — **로고 ≠ CNCF 프로젝트**. `project` 키의 유무가 그 경계입니다.

## Step 4. Graduated 전수 목록 — Part 4 심층 모듈의 대상

```bash
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
grads = []
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        for item in sub.get('items', []):
            if item.get('project') == 'graduated':
                grads.append((item['name'], cat['name'], sub['name']))
print(f"=== Graduated {len(grads)}개 (수집 시점 기준) ===")
for name, cat, sub in sorted(grads):
    print(f"{name:22s} {cat} / {sub}")
EOF
```

예상: Kubernetes, Prometheus, Envoy, Helm, Argo, Cilium, Istio, etcd, containerd... ✅ 이 목록이 11~44 심층 모듈의 명단입니다 — 루트 README 버전표(약 35개, 2026-06)와 대조하고, 다르면 **버전표를 갱신**하세요(이 커리큘럼의 유지 규율).

## Step 5. 내 스택 대조 — 이미 배운 것들의 위치 확인

```bash
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
learned = ['Kubernetes','Helm','Prometheus','Argo','Flux','containerd','CoreDNS',
           'etcd','Karpenter','KEDA','Open Policy Agent','Kyverno','in-toto','Tekton*']
idx = {}
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        for item in sub.get('items', []):
            idx[item['name'].lower()] = (item.get('project','(비프로젝트/제품)'), cat['name'])
print("=== 커리큘럼에서 이미 만난 것들 ===")
for n in learned:
    hit = idx.get(n.lower())
    print(f"{n:22s} {hit if hit else '→ landscape에 없음/이름 다름 (직접 검색: Tekton은 CDF!)'}")
EOF
```

예상: 대부분 graduated로 표시 — 그리고 **Tekton은 안 나옵니다**(CDF 소속 — cicd 28). ✅ k8s·eks·cicd에서 쓴 도구들이 지도 위 어디에 있는지 확인 — "이미 절반은 아는 동네"라는 감각과, 재단이 CNCF 하나가 아니라는 사실(CDF·LF 산하 형제들)까지.

## Step 6. 산출물 — 나의 지도 초안

```markdown
# landscape 집계 결과 (수집일 기입: ____)
- 전체 항목 수: ___ / CNCF 프로젝트: ___ (graduated ___ / incubating ___ / sandbox ___)
- 내가 프로덕션에서 쓰는 것 중 Sandbox 단계인 것: ___ (→ 지속성 리스크 점검 대상)
- 02~10에서 훑을 카테고리 축: Step 2의 출력 보관
- 루트 README 버전표와의 차이: ___ (있으면 갱신 PR... 아니, 갱신 편집)
```

## 정리

landscape.yml은 lab-02에서도 씁니다. 유지.
