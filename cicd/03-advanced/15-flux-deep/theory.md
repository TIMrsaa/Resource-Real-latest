# 이론 — 컨트롤러 조합, 리소스 관계, 이미지 자동화, 선택

> **🌱 17세 눈높이 비유: 올인원 프린터 vs 모듈형 오디오**
> - **ArgoCD** = 올인원 복합기: 인쇄·스캔·팩스가 한 몸체에 + 큰 터치스크린(UI). 하나로 다 되고 보기 편합니다
> - **Flux** = 모듈형 하이파이 오디오: 앰프·튜너·CD플레이어가 각각 따로(작은 컨트롤러들). 조합이 자유롭고 각 부품이 전문적이지만, 화면(UI)은 기본적으로 없습니다
> - **같은 음악(GitOps 원칙)** 을 틉니다 — 선언·git·pull·reconcile. 몸체 구성만 다릅니다
> - **이미지 자동화** = 새 앨범(이미지)이 나오면 자동으로 재생목록(git)에 추가하는 기능 — Flux는 이게 내장 부품, ArgoCD는 별매

---

## 1. 컨트롤러 조합 — Flux의 구조

```
Flux = 다섯 컨트롤러의 조합 (GitOps Toolkit)
┌──────────────────────────────────────────────────┐
│ source-controller     git/helm/oci 저장소를 가져와 캐시  │
│ kustomize-controller  가져온 것을 kustomize로 적용        │
│ helm-controller       HelmRelease를 조정                  │
│ image-reflector-ctrl  레지스트리 스캔(태그 발견)          │
│ image-automation-ctrl 새 이미지를 git에 커밋 (★내장)      │
│ notification-controller 이벤트 알림/수신(webhook)         │
└──────────────────────────────────────────────────┘
```

ArgoCD와 대조:

| | ArgoCD | Flux |
|---|---|---|
| 구조 | 하나의 앱(+UI) | 컨트롤러 조합(툴킷) |
| 단위 | Application CRD | GitRepository + Kustomization/HelmRelease |
| UI | 강력한 내장 대시보드 | 없음(별도 Weave GitOps/Capacitor) |
| 이미지 자동화 | 별도(Image Updater) | **내장**(image-controller) |
| 멀티테넌시 | Project | Kustomization + RBAC |
| 철학 | 배포 플랫폼 | 쿠버네티스 확장 툴킷 |

## 2. Flux 리소스 관계

```yaml
# ① GitRepository: "이 git을 가져와라" (source)
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata: { name: myapp }
spec:
  url: https://github.com/org/config-repo
  ref: { branch: main }
  interval: 1m                        # 폴링 주기 (reconcile)

---
# ② Kustomization: "가져온 것의 이 경로를 적용해라" (apply)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: myapp }
spec:
  sourceRef: { kind: GitRepository, name: myapp }
  path: ./apps/myapp
  prune: true                         # 14의 prune과 동일
  interval: 10m
  targetNamespace: myapp
```

핵심: **source(가져오기)와 apply(적용)가 분리**돼 있습니다 — 하나의 GitRepository를 여러 Kustomization이 공유하고, 각각 다른 경로/네임스페이스에 적용할 수 있습니다. ArgoCD의 Application이 이 둘을 합친 것과 대조.

이 분리의 이점: git을 한 번 가져와 fleet의 여러 앱에 재사용(대역폭·부하), source 종류 교체 용이(git→oci).

## 3. 이미지 자동화 — 14의 경계 ②를 내장으로

14에서 "이미지 태그를 누가 git에 업데이트하나"가 경계였습니다. Flux는 세 리소스로 자동화:

```yaml
# ① ImageRepository: 레지스트리를 스캔
kind: ImageRepository
spec: { image: ghcr.io/org/app, interval: 5m }

# ② ImagePolicy: 어떤 태그를 고를지 (semver, 정규식...)
kind: ImagePolicy
spec:
  imageRepositoryRef: { name: app }
  policy: { semver: { range: ">=1.0.0" } }   # 또는 최신 빌드

# ③ ImageUpdateAutomation: git에 커밋
kind: ImageUpdateAutomation
spec:
  sourceRef: { kind: GitRepository, name: myapp }
  git:
    commit: { author: { name: fluxbot } }
    push: { branch: main }
  update: { path: ./apps }
```

동작: 레지스트리에 새 이미지 → policy가 선택 → git 매니페스트를 자동 업데이트(커밋+push) → Kustomization이 그것을 감지해 배포. **CI-CD 접점이 완전 자동화**됩니다.

주의(04의 규율): 매니페스트에 `# {"$imagepolicy": "flux-system:app"}` 마커를 두면 그 자리가 자동 갱신됩니다. 그리고 이 자동 커밋이 CI를 다시 트리거하지 않도록 config repo 분리(14)가 여전히 중요.

## 4. Helm 통합 — HelmRelease

```yaml
kind: HelmRelease
spec:
  chart:
    spec: { chart: podinfo, sourceRef: { kind: HelmRepository, name: podinfo } }
  values: { replicaCount: 3 }
  interval: 10m
```

Flux의 helm-controller는 Helm을 **선언적으로** 만듭니다 — `helm install`을 사람이 실행하는 대신, HelmRelease가 git에 있고 컨트롤러가 조정합니다. eks 11의 Helm이 GitOps화된 형태. ArgoCD도 Helm을 지원하지만(Application의 source), Flux는 전용 컨트롤러로 더 깊습니다(값 병합, 롤백, 테스트 훅).

## 5. 선택 기준 — 설계 철학으로

| 상황 | 경향 |
|------|------|
| UI로 배포 상태를 보는 문화 | ArgoCD(강력한 대시보드) |
| 개발자 셀프서비스, 시각적 | ArgoCD |
| 이미지 자동화가 핵심 | Flux(내장) |
| 조합·확장, 다른 도구와 통합 | Flux(툴킷) |
| Helm 중심 | Flux(helm-controller) 또는 둘 다 |
| 멀티테넌시 세밀 제어 | 둘 다 가능(방식 다름) |

현실: 둘 다 CNCF Graduated, 둘 다 프로덕션급. 많은 조직이 **팀 문화**(UI 선호 vs CLI/GitOps 순수주의)로 고릅니다. 그리고 Argo Rollouts(17)는 ArgoCD와 잘 통합, Flux는 Flagger(17)와.

## 6. OpenGitOps — 도구 독립 원칙

```
1. Declarative: 시스템의 desired 상태를 선언적으로
2. Versioned & Immutable: git에 버전관리, 불변
3. Pulled Automatically: 에이전트가 자동으로 당김
4. Continuously Reconciled: 지속적으로 조정
```

ArgoCD든 Flux든 이 네 원칙을 구현합니다 — 도구는 구현이고 **원칙이 본질**입니다(12의 이식성). 이것을 이해하면 새 GitOps 도구(또는 자체 구축)도 이 원칙으로 평가할 수 있습니다.

## 7. 소스/도구에서 확인하기

- Flux: https://github.com/fluxcd/flux2 (CNCF Graduated — 27 기여 대상)
- GitOps Toolkit: https://fluxcd.io/flux/components/
- OpenGitOps: https://opengitops.dev
- ArgoCD vs Flux 비교(공식 중립 자료 없음 — 원칙으로 판단)

## 요약 카드

| 질문 | 답 |
|------|----|
| Flux 구조? | 컨트롤러 조합(source/kustomize/helm/image/notification) |
| ArgoCD와 철학 차이? | 올인원+UI vs 모듈형 툴킷 |
| source와 apply? | Flux는 분리(GitRepository + Kustomization), 재사용 용이 |
| 이미지 자동화? | Flux 내장(image-controller) — 14의 경계 ② 해결 |
| 선택 기준? | UI 문화(ArgoCD) vs 조합·자동화(Flux) — 우열 아닌 철학 |
| 본질? | OpenGitOps 4원칙 — 도구는 구현, 원칙이 본질(12) |
