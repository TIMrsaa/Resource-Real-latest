# Lab 02 — 층 통합과 GitOps 전체 조립

> lab-01에서 층을 손으로 쌓았습니다. 이 랩은 그것을 **GitOps app-of-apps**로 선언해 "플랫폼 = 코드"로 만들고, 층 사이의 통합점(메시 메트릭이 관측으로, 배포 상태가 관측으로)을 확인하고, 재현 가능성(클러스터를 잃어도 Git에서 재구축)을 이해합니다.

## 1. app-of-apps 구조 설계

플랫폼 전체를 Git 저장소로 표현합니다:

```
platform-repo/
  root-app.yaml              # 루트 Application (이것만 apply)
  platform/
    00-cert-manager.yaml     # sync-wave 0
    01-observability.yaml    # sync-wave 1
    02-security.yaml         # sync-wave 2
    03-mesh.yaml             # sync-wave 3
    04-apps.yaml             # sync-wave 4
```

```yaml
# root-app.yaml — 이 하나가 나머지를 배포 (app-of-apps)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/platform-repo
    path: platform
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated: { prune: true, selfHeal: true }
```

## 2. sync-wave로 순서 강제 (16의 순서 제어)

각 층 Application에 sync-wave를 붙여 lab-01의 순서를 GitOps가 강제하게 합니다:

```yaml
# platform/00-cert-manager.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"      # ★ 가장 먼저
spec:
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.14.0
    helm: { parameters: [{ name: crds.enabled, value: "true" }] }
  destination: { server: https://kubernetes.default.svc, namespace: cert-manager }
  syncPolicy:
    automated: {}
    syncOptions: [CreateNamespace=true]
---
# platform/01-observability.yaml → sync-wave: "1"
# platform/02-security.yaml      → sync-wave: "2"
# platform/03-mesh.yaml          → sync-wave: "3"
# platform/04-apps.yaml          → sync-wave: "4"
```

```bash
# 이론상 흐름 (실제 저장소가 있다면):
# kubectl apply -f root-app.yaml
# → ArgoCD가 platform/ 을 읽어 각 Application 생성
# → sync-wave 순서로: cert-manager(0) → 관측(1) → 보안(2) → 메시(3) → 앱(4)
# → lab-01의 손 순서가 코드로 강제됨

# 현재 클러스터(lab-01)에서 sync-wave 개념 확인
kubectl get applications -n argocd 2>/dev/null || echo "Application CRD (ArgoCD 설치됨)"
```

**핵심** — lab-01에서 손으로 지킨 순서를 sync-wave가 코드로 강제합니다. 이제 `git clone` + 루트 apply만으로 전체 플랫폼이 순서대로 조립됩니다 — **플랫폼이 코드**가 됐습니다.

## 3. 층 통합점 확인 — 메시 메트릭이 관측으로

lab-01에 메시(Linkerd, 가벼움)를 추가해 층이 서로 강화되는 것을 봅니다:

```bash
# Linkerd 설치 (25 — 운영 최소 메시)
curl -sL https://run.linkerd.io/install | sh 2>/dev/null || echo "linkerd CLI 필요"
# linkerd install --crds | kubectl apply -f -
# linkerd install | kubectl apply -f -

# 핵심: 메시가 관측 층과 통합되는 지점
# Linkerd/Istio는 프록시 메트릭을 Prometheus 형식으로 노출
# → 관측 층(lab-01의 Prometheus)이 자동으로 메시 골든 시그널을 수집
```

```
통합점 (theory 5절):
  메시(24·25) → 메트릭을 Prometheus(11)로 → Grafana 대시보드
  → 개별 프로젝트일 땐 없던 시너지:
     "모든 서비스 간 통신의 지연·성공률"이 자동으로 관측됨
  → 앱 코드 변경 없이 (메시가 프록시에서, 관측이 수집에서)
```

## 4. 배포 상태도 관측으로 (배포 ↔ 관측)

```bash
# ArgoCD도 메트릭을 노출 → 관측 층이 배포 건강도까지
kubectl -n argocd get svc argocd-metrics 2>/dev/null || echo "argocd-metrics 서비스"

# Prometheus가 ArgoCD 메트릭을 수집하면:
# - 동기화 상태(Synced/OutOfSync)
# - 동기화 실패
# - 앱별 건강도
# → 배포 층의 상태가 관측 층에 (플랫폼 자체를 관측)
```

**관찰** — 관측 층이 아래(클러스터·메시)뿐 아니라 옆(배포 ArgoCD)·자기 자신까지 관측합니다. 이것이 층이 통합된 플랫폼의 모습 — 모든 층이 관측 가능합니다.

## 5. 재현 가능성 — 재해 복구 (36과 연결)

```
플랫폼 = 코드(Git)의 값어치:
  클러스터를 통째로 잃어도:
    1. 새 K8s 클러스터 (기반 층)
    2. ArgoCD 설치 (뼈대)
    3. kubectl apply root-app.yaml
    4. → 전체 플랫폼이 sync-wave 순서로 재조립
  → 36(재해 복구)의 "복구 리허설"이 GitOps로 재현 가능
  → 단, 상태(etcd·DB·PV)는 별도 백업 (36·39·40 — 코드는 복원해도 데이터는 백업에서)

★ 플랫폼 구성(코드)과 데이터(상태)를 분리:
  구성 → Git에서 재현
  데이터 → 백업에서 복원 (Velero·스냅샷)
```

## 6. 전체 그림 회고

```
이 두 랩에서 조립한 것:
  기반(K8s·CNI·DNS) + GitOps(ArgoCD) + cert-manager
  + 관측(Prometheus·Grafana) + 정책(Kyverno) + 메시(Linkerd)
  → app-of-apps로 코드화, sync-wave로 순서, 층이 서로 관측·강화

여기에 47에서 더할 것:
  + 개발자 플랫폼(Backstage·Crossplane) → 셀프서비스
  = 완전한 IDP

48에서 정할 것:
  각 층의 선택 (Istio vs Linkerd vs Cilium 등)
```

## 7. 정리

```bash
pkill -f "port-forward" 2>/dev/null || true
# 전체 정리는 cleanup.sh
```

## 정리

- app-of-apps: 루트 Application 하나가 전체 층을 배포 → "플랫폼 = 코드"
- sync-wave(16)가 lab-01의 손 순서를 코드로 강제 (cert-manager 0 → 앱 4)
- 통합점: 메시 메트릭·배포 상태가 관측 층으로 → 층이 서로 강화(개별일 땐 없던 시너지)
- 재현: 클러스터를 잃어도 Git에서 재조립(구성) + 백업에서 복원(데이터, 36)
- **★ 프로젝트를 아는 것 + 층·의존·통합을 아는 것 = 플랫폼을 짓는 능력 (47로)**
