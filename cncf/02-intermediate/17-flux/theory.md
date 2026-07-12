# 이론 — GitOps Toolkit, 조합의 문법, HelmRelease, 이미지 자동화, 멀티테넌시

> **🌱 17세 눈높이 비유: 완성품 오디오 vs 조립 오디오**
> - **ArgoCD** = 일체형 오디오 — 사서 꽂으면 소리가 납니다. 화면도 예쁩니다
> - **Flux** = 컴포넌트 오디오 — 소스(턴테이블·CD·스트리밍), 앰프, 스피커를 따로 삽니다
>   - **source-controller** = 소스 기기 — Git·Helm 저장소·OCI에서 "자료"를 가져와 보관
>   - **kustomize-controller** = 앰프 A — 자료를 매니페스트로 만들어 클러스터에 적용
>   - **helm-controller** = 앰프 B — 자료를 Helm 릴리스로 설치·업그레이드
>   - **notification-controller** = 인터폰 — 이벤트를 슬랙·웹훅으로, 그리고 밖에서 오는 신호를 받아
> - **조합의 힘** = 턴테이블 하나를 앰프 둘이 공유할 수 있습니다 (GitRepository 하나 → Kustomization 여럿)
> - **이미지 자동화** = 라디오에서 새 곡이 나오면 자동으로 재생 목록에 적어두는 장치 (레지스트리 → Git 커밋)

---

## 1. GitOps Toolkit — 컨트롤러 4종과 CRD

```
┌─ source-controller ────────────────────────────────────┐
│  GitRepository / HelmRepository / OCIRepository /       │
│  Bucket / HelmChart                                      │
│  → 아티팩트를 fetch·검증·저장(내부 HTTP로 서빙)           │
└──────────┬──────────────────────────────┬───────────────┘
           │ (artifact URL)               │
┌──────────▼──────────┐        ┌──────────▼───────────┐
│ kustomize-controller │        │  helm-controller     │
│  Kustomization CR    │        │  HelmRelease CR      │
│  → build + apply     │        │  → helm install/upgrade
│  → health check·prune│        │  → 실제 Helm 릴리스   │
└──────────────────────┘        └──────────────────────┘
           │                               │
┌──────────▼───────────────────────────────▼───────────┐
│ notification-controller                               │
│  Alert / Provider (out) · Receiver (in: 웹훅)          │
└───────────────────────────────────────────────────────┘
(+) image-reflector-controller / image-automation-controller  → §4
```

**핵심 문법: 소스와 적용의 분리**

```yaml
# 소스 하나
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata: { name: platform, namespace: flux-system }
spec: { url: https://github.com/org/gitops, ref: { branch: main }, interval: 1m }
---
# 그것을 참조하는 적용 여럿 (각자 다른 path·주기·의존성)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: infra }
spec: { sourceRef: { kind: GitRepository, name: platform }, path: ./infra, prune: true, interval: 10m }
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: apps }
spec:
  sourceRef: { kind: GitRepository, name: platform }
  path: ./apps
  dependsOn: [{ name: infra }]          # ★ 순서(ArgoCD의 sync wave에 대응)
  prune: true
  interval: 5m
```

- **한 소스를 여러 적용이 공유** — clone 한 번, 여러 목적. ArgoCD는 Application마다 source를 갖습니다
- `dependsOn` — 컨트롤러 수준의 의존성(infra가 Ready여야 apps 적용)
- `interval` — 각 CR이 자기 주기를 갖습니다(소스 fetch 주기 ≠ 적용 주기)

## 2. 조정 모델 — ArgoCD와의 대비

| | ArgoCD | Flux |
|---|---|---|
| 단위 | Application(소스+적용 한 몸) | Source CR + 적용 CR(분리) |
| 상태 표시 | 강력한 UI | CR의 status·조건, `flux get` |
| 순서 | sync wave(어노테이션) | `dependsOn`(CR 필드) |
| 드리프트 | selfHeal(옵션) | 적용 주기마다 재적용(기본이 수렴) |
| 삭제 | prune(옵션) | `prune: true` |
| 헬스 | gitops-engine의 health | `healthChecks` + 커스텀 |
| 접근 | 중앙 서버 + RBAC | **네임스페이스 스코프 CR + SA 임퍼소네이션** |
| 확장 | ApplicationSet, 플러그인 | **툴킷 컨트롤러 조합, 다른 프로젝트가 재사용** |

## 3. HelmRelease — Helm의 상태 기계를 살립니다 (15와 연결)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata: { name: podinfo, namespace: apps }
spec:
  interval: 10m
  chart:
    spec:
      chart: podinfo
      version: "6.x"
      sourceRef: { kind: HelmRepository, name: podinfo, namespace: flux-system }
  values: { replicaCount: 2 }
  install: { remediation: { retries: 3 } }
  upgrade: { remediation: { retries: 3, remediateLastFailure: true } }   # 실패 시 자동 롤백
  driftDetection: { mode: enabled }         # 클러스터 드리프트 감지·교정
  # 시크릿을 values로: valuesFrom(Secret/ConfigMap) — cicd 22와 결합
```

- helm-controller가 **실제 Helm 릴리스**를 만듭니다 → `helm history`·`helm rollback` 유효, 차트의 훅 온전히 동작(15)
- `remediation`: 업그레이드 실패 시 자동 롤백(재시도 횟수 지정) — ArgoCD에는 대응이 다름
- SOPS 복호화 내장(`decryption.provider: sops`) — cicd 22의 GitOps 시크릿 해법 중 SOPS 노선의 1급 지원

## 4. 이미지 자동화 — 레지스트리에서 Git으로

```yaml
ImageRepository  # 레지스트리를 스캔 (태그 목록)
ImagePolicy      # 정책으로 최신 태그 선택 (semver / numerical / alphabetical + 필터)
ImageUpdateAutomation  # 선택된 태그를 Git의 매니페스트에 써넣고 커밋·푸시
```

```yaml
# 매니페스트에 마커를 남겨둡니다
image: ghcr.io/org/app:1.2.3 # {"$imagepolicy": "flux-system:app-policy"}
```

```
루프: CI가 이미지 push → ImageRepository가 감지 → ImagePolicy가 태그 선택
    → ImageUpdateAutomation이 Git에 커밋 → GitRepository가 감지 → Kustomization이 적용
★ "push→pull 역전"(cicd 14)의 완성형 — CI는 레지스트리까지만, 배포는 클러스터가 당깁니다
주의: 자동 커밋이 main에 직접 들어가면 리뷰가 없습니다 → 별도 브랜치 + PR 자동 생성 패턴 권장
      태그 정책이 느슨하면(latest·alphabetical) 원치 않는 이미지가 프로덕션으로
```

## 5. 멀티테넌시 — 네임스페이스와 임퍼소네이션

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: team-a, namespace: team-a }
spec:
  serviceAccountName: team-a-reconciler    # ★ 이 SA의 권한으로 적용합니다
  sourceRef: { kind: GitRepository, name: team-a-repo }
  path: ./
  prune: true
```

```
Flux의 테넌시 모델:
  - CR이 네임스페이스 스코프 → 팀 네임스페이스에 자기 Kustomization/HelmRelease
  - serviceAccountName 임퍼소네이션 → 그 SA의 RBAC를 넘는 배포 불가 (K8s RBAC가 경계)
  - 크로스 네임스페이스 참조를 막는 설정(--no-cross-namespace-refs) 필수
★ ArgoCD는 중앙 서버의 AppProject·RBAC가 경계(16), Flux는 K8s RBAC가 경계
  → "K8s RBAC를 이미 쓰고 있다"면 Flux의 모델이 자연스럽습니다
```

## 6. 관측과 알림

```yaml
Alert / Provider (notification-controller):
  이벤트(적용 성공·실패·드리프트)를 Slack·Teams·웹훅·GitHub commit status로
Receiver:
  GitHub 웹훅을 받아 즉시 reconcile 트리거 (폴링 대기 제거 — 16의 webhook과 같은 이유)
메트릭: 각 컨트롤러가 Prometheus 메트릭 노출 (gotk_reconcile_duration_seconds 등)
```

## 7. 선택 기준 (48의 예고)

```
Flux가 맞는 조직:
  - K8s RBAC·네임스페이스로 테넌시를 이미 운영 (경계 모델이 일치)
  - CR 중심 운영에 익숙, UI 의존이 적음, 자동화·플랫폼 내재화 지향
  - Helm 릴리스 상태 기계를 유지하고 싶습니다(15)
  - 이미지 자동화로 완전 pull 루프를 원합니다
ArgoCD가 맞는 조직:
  - 개발자에게 배포 상태를 보여주는 UI가 중요
  - 중앙 집중 거버넌스(AppProject·RBAC)와 다중 클러스터 단일 뷰
  - 앱 단위 사고(하나의 Application = 하나의 앱)
★ 둘 다 CNCF Graduated이고, 둘 다 옳습니다. 조직의 성질과 맞추는 문제입니다
```

## 8. 소스/도구에서 확인하기

- Flux 문서: https://fluxcd.io/flux/ — components, multi-tenancy, image automation
- GitOps Toolkit API: https://fluxcd.io/flux/components/
- Flagger(Flux 위에 지어진 것): https://flagger.app
- cicd 15 복습: 사용자 관점

## 요약 카드

| 질문 | 답 |
|------|----|
| 설계 철학? | 제품(ArgoCD) vs **툴킷**(Flux — 컨트롤러 4종의 조합) |
| 핵심 문법? | 소스(GitRepository)와 적용(Kustomization/HelmRelease)의 **분리·재사용** |
| 순서 제어? | `dependsOn`(CR 필드) — ArgoCD의 sync wave에 대응 |
| HelmRelease? | 실제 Helm 릴리스를 만듭니다 → history·rollback·훅 유효(15의 긴장을 이렇게 풉니다) |
| 자동 롤백? | `upgrade.remediation` — 실패 시 재시도·롤백 내장 |
| 이미지 자동화? | 레지스트리 스캔 → 정책으로 태그 선택 → Git에 커밋 (완전 pull 루프) |
| 테넌시 경계? | 네임스페이스 CR + **SA 임퍼소네이션**(K8s RBAC가 경계) |
| 선택 기준? | UI·중앙 거버넌스면 ArgoCD, RBAC 경계·CR 중심·Helm 상태 유지면 Flux |
