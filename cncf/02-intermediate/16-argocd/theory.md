# 이론 — 부하의 해부, 샤딩, 멀티클러스터 아키텍처, ApplicationSet, 거버넌스

> **🌱 17세 눈높이 비유: 전국 편의점 본사의 관리 시스템**
> - **application-controller** = 본사 감독관 — 전국 점포(클러스터)를 계속 확인하고 매뉴얼(Git)과 다르면 고칩니다
> - **repo-server** = 매뉴얼 인쇄실 — 본사 규정(차트·오버레이)을 점포별 매뉴얼로 인쇄. 같은 규정을 수백 번 인쇄하면? **복사본을 캐시**해야 합니다
> - **redis** = 인쇄실 창고 — 캐시가 날아가면 전부 다시 인쇄(느려집니다)
> - **샤딩** = 감독관을 여러 명 두고 지역을 나눠 담당
> - **감춰진 부하** = 각 점포의 직원(대상 클러스터 API 서버)이 감독관의 질문에 계속 답하느라 바쁩니다
> - **AppProject** = 감독관의 권한 범위 — "이 감독관은 서울 지역, 이 매뉴얼만"
> - **ApplicationSet** = 점포 목록에서 자동으로 감독 대상을 생성하는 규칙

---

## 1. 컴포넌트별 부하 특성 — 어디가 먼저 무너지나

| 컴포넌트 | 하는 일 | 병목 | 확장 |
|---|---|---|---|
| **repo-server** | Git fetch + helm template/kustomize build | **CPU·디스크·동시성** | replicas↑, `--parallelismlimit`, 캐시 |
| **application-controller** | 클러스터 watch, diff, sync 실행 | **메모리(캐시)·리스트 부하** | **샤딩**(클러스터 단위) |
| redis | 렌더 결과·리소스 트리 캐시 | 메모리, 단일 인스턴스 | HA(redis-ha), 크기 |
| server(API/UI) | 사용자 요청, RBAC | 대개 문제 아님 | replicas↑ |
| **대상 클러스터 API** | ArgoCD의 watch를 응대 | ⚠️ 감춰진 부하 | 리소스 제외(§2) |

```
전형적 증상 → 원인:
  "sync가 오래 걸린다"            → repo-server 렌더링 대기열 (동시성·캐시)
  "OutOfSync 감지가 늦다"         → controller의 리스트/watch 지연, 3분 주기 밀림
  "controller OOM"               → 클러스터 리소스 캐시(모든 리소스 watch!) → 제외 설정·샤딩
  "대상 클러스터 API가 바쁘다"     → ArgoCD의 watch — 대상 리소스 종류를 줄여라
  "전체가 갑자기 느려짐"          → redis 다운/축출 → 전 앱 재렌더
```

## 2. 규모 운영의 손잡이

```yaml
# ① 리소스 추적 범위 축소 — controller 메모리와 대상 API 부하를 동시에 줄입니다
#    argocd-cm: resource.exclusions — 필요 없는 종류를 watch에서 제외
resource.exclusions: |
  - apiGroups: ["cilium.io"]
    kinds: ["CiliumIdentity", "CiliumEndpoint"]     # 수만 개 생기는 것들
    clusters: ["*"]
  - apiGroups: ["*"]
    kinds: ["Event", "EndpointSlice"]

# ② 샤딩 — 클러스터를 컨트롤러 인스턴스에 분배
#    controller StatefulSet replicas + ARGOCD_CONTROLLER_REPLICAS
#    sharding.algorithm: legacy | round-robin | consistent-hashing
#    ★ 샤딩은 '클러스터' 단위 — 한 클러스터의 앱이 많으면 그 샤드가 무겁습니다

# ③ repo-server 캐시·동시성
#    --parallelismlimit N (동시 매니페스트 생성 수)
#    --repo-cache-expiration, redis 크기
#    같은 저장소·리비전의 렌더 결과는 캐시 히트 (모노레포에 유리)

# ④ reconcile 주기
#    timeout.reconciliation (기본 180s) — 늘리면 부하↓ 반응↓ (웹훅으로 보완)
#    webhook(GitHub) 설정이 사실상 필수 — 폴링에 의존하지 마세요
```

## 3. 멀티클러스터 아키텍처 3형태

```
[A] 중앙집중 (ArgoCD 1개 → 클러스터 N개)
    ✅ 단일 UI·정책, 운영 단순
    ❌ SPOF, 자격증명 집중(07의 신뢰 경계), 네트워크 경계 통과, 샤딩으로도 한계

[B] 허브-스포크 (리전/환경별 ArgoCD, 상위에서 부트스트랩)
    ✅ 폭발 반경 축소, 리전 내 지연 낮음
    ❌ 여러 ArgoCD의 일관성(버전·정책)을 별도 관리

[C] 클러스터별 ArgoCD (self-managed)
    ✅ 최대 격리, 클러스터가 자기 자신을 관리(app-of-apps로 부트스트랩)
    ❌ 전역 뷰 상실, 운영 대상 N배

판단 축: 클러스터 수, 규제(자격증명 격리), 폭발 반경 허용치, 팀 구조
★ 대상 클러스터 자격증명(kubeconfig)이 중앙에 모인다는 사실 —
  ArgoCD 침해 = 전 클러스터 침해. 07의 시간선에서 이 지점의 방어를 설계하세요
```

## 4. ApplicationSet — 앱을 만드는 앱

```yaml
spec:
  generators:
    - list:        { elements: [{cluster: prod, url: https://...}] }   # 정적 목록
    - clusters:    { selector: { matchLabels: { env: prod } } }        # 등록된 클러스터에서
    - git:
        repoURL: ...
        directories: [{ path: "apps/*" }]        # 디렉터리 = 앱 (모노레포 — cicd 20)
        # 또는 files: [{ path: "envs/*/config.json" }]  ← 파일 내용이 파라미터
    - matrix:      { generators: [...] }         # 곱집합 (클러스터 × 앱)
    - merge:       { generators: [...] }         # 병합(override)
    - pullRequest: { github: {...} }             # PR마다 프리뷰 환경!
  template:
    metadata: { name: "{{path.basename}}-{{cluster}}" }
    spec: { project: ..., source: {...}, destination: {...} }
  # 안전장치
  syncPolicy: { applicationsSync: create-update }   # 생성/갱신만, 삭제 금지 옵션
  strategy: { type: RollingSync, rollingSync: { steps: [...] } }  # 점진 롤아웃
```

**생성기의 힘과 위험**: 라벨 하나를 바꾸면 수백 Application이 생기거나 **사라집니다**(= 워크로드 삭제). `applicationsSync: create-update`와 `preserveResourcesOnDeletion`으로 방어하고, 변경은 항상 `--dry-run`·PR 리뷰로.

### app-of-apps

```
루트 Application → Git의 apps/ 디렉터리 → 각 파일이 또 다른 Application
  = "부트스트랩 하나로 전부 배포". ApplicationSet 이전의 관용 패턴이며 여전히 유용
  (ArgoCD 자신을 self-manage 하는 데도 쓰입니다)
```

## 5. 거버넌스 — AppProject와 RBAC

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: { name: team-a }
spec:
  sourceRepos: ["https://github.com/org/team-a-*"]        # 이 팀이 쓸 수 있는 저장소
  destinations:
    - { server: "https://kubernetes.default.svc", namespace: "team-a-*" }  # 배포 가능 목적지
  clusterResourceWhitelist: []                            # 클러스터 스코프 리소스 금지
  namespaceResourceBlacklist:
    - { group: "", kind: "ResourceQuota" }                # 쿼터는 못 건드림
  roles:
    - name: deployer
      policies: ["p, proj:team-a:deployer, applications, sync, team-a/*, allow"]
```

```
RBAC (argocd-rbac-cm):
  g, org:sre, role:admin
  p, role:dev, applications, get, */*, allow
  p, role:dev, applications, sync, dev-*/*, allow      # dev만 sync 가능
  p, role:dev, applications, sync, prod-*/*, deny      # prod는 거부
★ cicd 24의 "강제는 좁게": AppProject가 소스·목적지·리소스 종류를 좁히고,
  RBAC가 행위(sync·delete·override)를 좁힙니다. 둘 다 필요합니다.
```

## 6. Flux와의 대비 예고 (17·48)

```
ArgoCD: 단일 컨트롤러 + 강력한 UI + Application CRD 하나 → "제품형"
Flux:   컨트롤러 조합(source/kustomize/helm/notification) → "라이브러리형"
        (17에서 심화, 48에서 선택 가이드)
```

## 7. 소스/도구에서 확인하기

- 확장성 문서: https://argo-cd.readthedocs.io/en/stable/operator-manual/high_availability/
- 리소스 제외: `argocd-cm`의 `resource.exclusions`
- ApplicationSet: https://argocd-applicationset.readthedocs.io
- AppProject/RBAC: operator-manual/rbac
- cicd 27: 소스 구조 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| 첫 병목? | repo-server(렌더링 CPU·동시성) — sync 지연의 1번 원인 |
| controller OOM? | 대상 클러스터의 모든 리소스 watch — resource.exclusions로 축소, 샤딩 |
| 감춰진 부하? | 대상 클러스터 API 서버 — ArgoCD의 watch가 그것을 바쁘게 합니다 |
| redis? | 캐시 SPOF — 죽으면 전 앱 재렌더로 폭풍 |
| 멀티클러스터 3형태? | 중앙집중(SPOF·자격증명 집중) / 허브-스포크 / 클러스터별(격리·운영 N배) |
| ApplicationSet의 위험? | 생성기 파라미터 변경이 수백 앱을 **삭제**할 수 있습니다 — create-update·preserve 옵션 |
| 거버넌스 2층? | AppProject(소스·목적지·리소스 화이트리스트) + RBAC(행위 제한) |
