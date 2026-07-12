# Lab 01 — 네트워킹 전수 조사: 서브카테고리 4곳을 층으로 병합

네트워킹은 landscape에서 여러 칸(CNI·Coordination·Service Proxy·API Gateway·Service Mesh)에 흩어져 있습니다 — 전부 뽑아 theory의 층으로 재조립합니다.

전제: 01 lab-01의 landscape.yml.

## Step 1. 흩어진 칸들을 전수 수집

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
targets = ['Cloud Native Network', 'Coordination & Service Discovery',
           'Service Proxy', 'API Gateway', 'Service Mesh', 'Remote Procedure Call']
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        if not any(t.lower() in sub['name'].lower() for t in targets): continue
        items = sub.get('items', [])
        cncf = [i for i in items if i.get('project')]
        print(f"\n=== {sub['name']} — {len(items)}개 (CNCF {len(cncf)}) ===")
        for it in sorted(cncf, key=lambda x: x['name'].lower()):
            print(f"{it['project']:12s} {it['name']}")
EOF
```

예상: Network 칸에 Cilium(graduated)·Antrea 등, Service Proxy에 Envoy·Contour, Service Mesh에 Istio·Linkerd·Kuma, RPC에 gRPC. ✅ 한 "네트워킹"이 landscape에서는 대여섯 칸 — **우리의 층 모델이 지도보다 실용적**임을 확인(칸은 전시용, 층은 결정용).

## Step 2. Envoy 계보 표시 — 로고 뒤의 공용 부품

```bash
python3 <<'EOF'
# Envoy를 데이터플레인으로 쓰는 프로젝트들 (theory §3의 계보)
envoy_family = ['Istio','Contour','Emissary','Envoy Gateway','Kuma']
own_dataplane = [('Linkerd','자체 Rust 프록시'),('Cilium','eBPF(+Envoy L7)'),
                 ('NGINX Ingress','NGINX'),('Traefik','자체 Go')]
print("=== Envoy 위에 지어진 것들 ===")
for p in envoy_family: print(f"  {p:16s} — 설정 생성기 (xDS로 Envoy를 조종)")
print("\n=== 자기 데이터플레인 ===")
for p, d in own_dataplane: print(f"  {p:16s} — {d}")
print("\n→ '게이트웨이/메시 선택'의 절반은 사실 '데이터플레인 선택'이다")
EOF
```

✅ 채택 회의에서 "Contour vs Emissary"를 논할 때 — 데이터플레인은 둘 다 Envoy이므로 실제 쟁점은 컨트롤플레인의 API·운영 모델뿐임을 아는 것. 계보를 그리면 비교 항목이 줄어듭니다.

## Step 3. 성숙도·건강검진 — 이 지도의 Graduated 밀집 확인

```bash
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
grads = []
targets = ['Network','Service Proxy','API Gateway','Service Mesh','Coordination','Remote Procedure']
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        if not any(t.lower() in sub['name'].lower() for t in targets): continue
        for it in sub.get('items', []):
            if it.get('project') == 'graduated': grads.append(it['name'])
print(f"네트워킹 계열 Graduated: {len(grads)}개 — {sorted(grads)}")
EOF

# 건강검진 1건 — 이번엔 Incubating에서 (예: Contour)
R="projectcontour/contour"
gh api "repos/$R/releases?per_page=3" --jq '.[] | "\(.tag_name)  \(.published_at)"'
gh api "repos/$R/contributors?per_page=5" --jq '.[].login'
```

✅ guide의 주장("Graduated 밀집 지대")을 숫자로 확인 + 01의 소견서 근육 1회.

## Step 4. 산출물

```markdown
# 네트워킹 지도 — 조사 결과 (조사일: ____)
- 우리 스택의 현재 층 구성: CNI ___ / DNS CoreDNS / 인그레스 ___ / 메시 ___
- Envoy 계보 여부: 우리 게이트웨이·메시의 데이터플레인은 ___
- 변동 관찰: Gateway API 구현체 성숙도, Cilium 메시, ambient — 6개월 뒤 재확인 목록
- 건강검진 소견 1건: ___
```

## 정리

landscape.yml 유지.
