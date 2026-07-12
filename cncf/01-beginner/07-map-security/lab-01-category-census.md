# Lab 01 — 보안 전수 조사: 시간선에 배치하기

landscape의 보안(Provisioning/Security & Compliance 등) 칸을 뽑아 수명주기 시간선으로 재배치합니다 — 이미 아는 도구들에 좌표를 줍니다.

전제: 01 lab-01의 landscape.yml.

## Step 1. 보안 관련 서브카테고리 전수

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
kw = ['security','compliance','key management','identity']
for cat in data['landscape']:
    for sub in cat.get('subcategories', []):
        if not any(k in sub['name'].lower() for k in kw): continue
        items = sub.get('items', [])
        cncf = [i for i in items if i.get('project')]
        print(f"\n=== {cat['name']} / {sub['name']} — {len(items)}개 (CNCF {len(cncf)}) ===")
        for it in sorted(cncf, key=lambda x: x['name'].lower()):
            print(f"{it['project']:12s} {it['name']}")
EOF
```

예상: Falco·OPA·Kyverno·cert-manager·SPIFFE/SPIRE·in-toto·TUF·Harbor 등 (Graduated 다수) + 상용 스캐너·CSPM 로고 다수.

## Step 2. 시간선 배치 — 이미 아는 것에 좌표 주기

```bash
python3 <<'EOF'
timeline = {
 '빌드 전 (공급망)':   [('sigstore/cosign','cicd 21 — 서명'),('in-toto','증명 연쇄'),
                        ('TUF','업데이트 신뢰'),('Trivy*','스캔 — 비CNCF')],
 '배포 시점 (admission)':[('OPA/Gatekeeper','cicd 24 — rego'),('Kyverno','cicd 21 — verifyImages')],
 '실행 중 (런타임)':    [('Falco','시스템콜 탐지'),('Tetragon','eBPF — Cilium 계열')],
 '관통 — 신원':        [('cert-manager','인증서 자동화'),('SPIFFE/SPIRE','워크로드 ID')],
 '관통 — 정책':        [('OPA','범용'),('Kyverno','K8s 네이티브')],
}
for phase, items in timeline.items():
    print(f"\n[{phase}]")
    for n, d in items: print(f"   {n:20s} {d}")
print("\n→ 우리 스택을 이 시간선에 얹어 '빈 칸'을 찾는 것이 이 지도의 목적")
EOF
```

✅ 절반이 cicd에서 이미 만난 도구 — 지도의 일은 그것들에게 **시간선 좌표**를 주고, 우리 스택의 공백(예: 런타임 탐지 부재)을 드러내는 것.

## Step 3. 우리 스택의 공백 진단 — 자가 점검

```bash
cat <<'EOF'
# 우리 클러스터의 보안 시간선 자가 점검 (✅/❌ 표시)
[ ] 빌드 전: 이미지 서명? SBOM 생성·보관? 스캔 게이트?           (cicd 21)
[ ] 배포 시점: admission 정책 엔진? 서명 검증 강제?              (cicd 21 · k8s 34)
[ ] 실행 중: 런타임 탐지(Falco류)? — 대개 여기가 비어 있다 ★
[ ] 신원: cert-manager로 TLS 자동화? mTLS(메시)?                (eks 20)
[ ] 시크릿: OIDC 우선? 스토어? (cicd 22)
→ ❌가 곧 다음 도입 우선순위 — 공백은 대개 '런타임'과 '신원'에 있습니다
EOF
```

## Step 4. 건강검진 1건

```bash
R="falcosecurity/falco"
gh api "repos/$R/releases?per_page=3" --jq '.[] | "\(.tag_name)  \(.published_at)"'
gh api "repos/$R/contributors?per_page=5" --jq '.[].login'
echo "→ Falco는 Graduated — 유지보수자 다양성·릴리스 리듬을 01 소견서로"
```

## Step 5. 산출물

```markdown
# 보안 지도 — 조사 결과 (조사일: ____)
- 시간선 자가 점검 결과: 빌드전 __ / 배포시점 __ / 런타임 __ / 신원 __
- 최대 공백: ___ (다음 도입 후보)
- 정책 엔진 현황: OPA / Kyverno / 없음 — 향후 방향: ___
- 심층 예약: 30(Falco) 31(OPA) 32(Kyverno) 33(SPIFFE) 34(Harbor)
```

## 정리

landscape.yml 유지.
