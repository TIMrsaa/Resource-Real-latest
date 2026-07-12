# Lab 01 — 앱 배포 전수 조사: 사다리에 세우기

가장 붐비는 칸을 사다리 5단으로 정렬합니다 — 로고 늪을 구조로.

전제: 01 lab-01의 landscape.yml.

## Step 1. App Definition & Development 전수

```bash
cd ~/cncf-lab/landscape
python3 <<'EOF'
import yaml
data = yaml.safe_load(open('landscape.yml'))
for cat in data['landscape']:
    if 'App Definition' not in cat['name']: continue
    total = 0
    for sub in cat.get('subcategories', []):
        items = sub.get('items', [])
        cncf = [i for i in items if i.get('project')]
        total += len(items)
        print(f"\n=== {sub['name']} — {len(items)}개 (CNCF {len(cncf)}) ===")
        for it in sorted(cncf, key=lambda x: x['name'].lower()):
            print(f"{it['project']:12s} {it['name']}")
    print(f"\n▶ 대분류 총 {total}개 항목 — landscape에서 가장 붐비는 칸 중 하나")
EOF
```

예상: Application Definition(Helm·Kustomize·Operator Framework), Continuous Integration & Delivery(ArgoCD·Flux·Keptn·Tekton*), Database·Streaming(09의 영토) 등이 섞여 있습니다. **서브카테고리가 사다리와 일치하지 않습니다** — 그래서 우리가 다시 세웁니다.

## Step 2. 사다리 정렬 — 이 지도의 핵심 산출물

```bash
python3 <<'EOF'
ladder = {
 '1 매니페스트':   [('(kubectl/YAML)','k8s 초급')],
 '2 패키징':       [('Helm (Graduated)','템플릿+values'),('Kustomize (k8s-sigs)','오버레이 패치')],
 '3 배달':         [('Argo CD (Graduated)','cicd 14'),('Flux (Graduated)','cicd 15')],
 '4 점진 전환':    [('Argo Rollouts','cicd 17'),('Flagger (Flux 계열)','cicd 17')],
 '5 상위 추상':    [('Knative (Incubating)','워크로드 위'),('Dapr (Graduated)','앱 코드 위'),
                    ('Crossplane (Graduated)','클라우드 인프라 위'),('Backstage (Incubating)','조직 위'),
                    ('KubeVirt (Incubating)','VM 위')],
 '관통 — 오퍼레이터':[('Operator Framework/SDK','작성·OLM'),('Kubebuilder','스캐폴딩')],
}
for rung, items in ladder.items():
    print(f"\n[{rung}]")
    for n, d in items: print(f"   {n:28s} {d}")
print("\n→ 비교는 같은 단끼리만. 'Helm vs ArgoCD'(2 vs 3)는 함께 쓰는 관계다")
EOF
```

## Step 3. 5단 구분 훈련 — "무엇 위의 추상인가"

```bash
cat <<'EOF'
각 프로젝트의 README 첫 문단을 열어 "무엇 위인지" 한 단어로 적어보세요:
  Knative    → 워크로드(서빙): 스케일 투 제로가 핵심 능력
  Dapr       → 앱 코드(런타임): 사이드카 API — 상태·pub/sub·시크릿
  Crossplane → 클라우드 인프라: RDS/S3를 CR로 (오퍼레이터의 극단)
  Backstage  → 조직: 카탈로그·템플릿·문서 (개발자 경험)
  KubeVirt   → VM: 가상머신을 Pod처럼
★ 이 네 개를 헷갈리지 않는 것이 47(플랫폼 엔지니어링)의 전제 지식
EOF
gh api repos/crossplane/crossplane --jq '.description'
gh api repos/dapr/dapr --jq '.description'
gh api repos/knative/serving --jq '.description'
gh api repos/backstage/backstage --jq '.description'
```

## Step 4. 오퍼레이터 성숙도 모델 — 채점표 익히기

```bash
cat <<'EOF'
Operator Capability Levels (theory §3) — 05의 Rook, 09의 Strimzi 평가에 그대로:
  L1 Basic Install     설치만
  L2 Seamless Upgrades 무중단 업그레이드
  L3 Full Lifecycle    백업·복구·페일오버
  L4 Deep Insights     메트릭·알람·로그 통합
  L5 Auto Pilot        자동 튜닝·자동 스케일·이상 자동 복구
질문: 우리가 프로덕션에 쓰는 오퍼레이터는 몇 레벨인가요? L3 미만이면 백업·복구는 우리 몫입니다.
EOF
```

## Step 5. 건강검진 1건

```bash
R="crossplane/crossplane"
gh api "repos/$R/releases?per_page=3" --jq '.[] | "\(.tag_name)  \(.published_at)"'
gh api "repos/$R/contributors?per_page=5" --jq '.[].login'
echo "→ 5단 도구는 특히 '추상 누수 시 디버깅 자료'(문서·이슈 품질)를 소견서에 추가하라"
```

## Step 6. 산출물

```markdown
# 앱 배포 지도 — 조사 결과 (조사일: ____)
- 우리 사다리: 2단 ___ / 3단 ___ / 4단 ___ / 5단 ___
- 렌더링 시점 정책: CI 렌더 / CD 렌더 — 근거: ___
- 오퍼레이터 인벤토리와 각 Capability Level: ___
- 5단 도입 검토 시 필수 질문: "덮이는 아래 단을 팀이 아는가요?" (추상 누수)
- 심층 예약: 15(Helm) 16(ArgoCD) 17(Flux) 29(Dapr) 41(Crossplane) 42(Backstage) 43(Knative)
```

## 정리

landscape.yml 유지.
