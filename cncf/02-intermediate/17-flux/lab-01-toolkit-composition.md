# Lab 01 — 툴킷의 조합: 소스 하나, 적용 여럿, 그리고 의존성

Flux의 설계 철학을 CR 조합으로 직접 확인합니다 — ArgoCD의 Application 하나와 무엇이 다른지.

전제: kind, kubectl, flux CLI(`brew install fluxcd/tap/flux`).

## Step 1. 클러스터와 Flux 설치

```bash
kind create cluster --name flux -q
flux check --pre
flux install --components=source-controller,kustomize-controller,helm-controller,notification-controller
kubectl -n flux-system get deploy
```

✅ **컨트롤러가 넷**입니다(ArgoCD는 하나의 큰 컨트롤러 + 보조들). 각각 독립 CRD를 감시합니다.

```bash
kubectl get crd | grep toolkit.fluxcd.io | head -8
```

## Step 2. 소스 하나 — GitRepository

```bash
flux create source git podinfo \
  --url=https://github.com/stefanprodan/podinfo \
  --branch=master \
  --interval=1m \
  --export > /tmp/source.yaml
cat /tmp/source.yaml
kubectl apply -f /tmp/source.yaml
sleep 20

kubectl -n flux-system get gitrepository podinfo
kubectl -n flux-system get gitrepository podinfo -o jsonpath='{.status.artifact.revision}'; echo
```

✅ source-controller가 저장소를 fetch해 **아티팩트로 보관**합니다(내부 HTTP로 서빙). 이 아티팩트를 여러 컨트롤러가 공유합니다 — 이것이 핵심.

## Step 3. 적용 둘 — 같은 소스를 참조

```bash
kubectl apply -f - <<'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: podinfo-a, namespace: flux-system }
spec:
  interval: 2m
  path: ./kustomize
  prune: true
  sourceRef: { kind: GitRepository, name: podinfo }
  targetNamespace: env-a
  healthChecks:
    - { apiVersion: apps/v1, kind: Deployment, name: podinfo, namespace: env-a }
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: podinfo-b, namespace: flux-system }
spec:
  interval: 5m                       # ★ 다른 주기!
  path: ./kustomize
  prune: true
  sourceRef: { kind: GitRepository, name: podinfo }   # ★ 같은 소스
  targetNamespace: env-b
  dependsOn: [{ name: podinfo-a }]   # ★ a가 Ready여야 b 적용
EOF
kubectl create ns env-a; kubectl create ns env-b
sleep 60

flux get kustomizations
kubectl -n env-a get deploy 2>/dev/null; kubectl -n env-b get deploy 2>/dev/null
```

예상: 두 Kustomization이 **하나의 GitRepository를 공유**하고, 각자 다른 네임스페이스·주기로 적용됩니다. b는 a를 기다립니다. ✅ **소스와 적용의 분리**(theory §1) — ArgoCD였다면 Application 두 개가 각각 저장소를 참조했을 것입니다(clone도 렌더링도 각각).

## Step 4. 의존성 확인 — dependsOn의 실물

```bash
# a를 일부러 실패시키면 b는?
kubectl -n flux-system patch kustomization podinfo-a --type merge \
  -p '{"spec":{"path":"./does-not-exist"}}'
sleep 40
flux get kustomizations
echo "→ podinfo-a가 실패하면 podinfo-b는 적용을 보류합니다 (dependsOn)"

kubectl -n flux-system patch kustomization podinfo-a --type merge -p '{"spec":{"path":"./kustomize"}}'
sleep 30
flux get kustomizations
```

✅ `dependsOn`은 ArgoCD의 sync wave와 같은 문제(순서)를 다른 층에서 풉니다 — 어노테이션이 아니라 **CR 필드**이고, 컨트롤러가 조건(Ready)을 보고 판단합니다.

## Step 5. HelmRelease — Helm 릴리스가 진짜로 만들어집니다

```bash
flux create source helm podinfo-helm \
  --url=https://stefanprodan.github.io/podinfo --interval=10m >/dev/null
sleep 15

kubectl apply -f - <<'EOF'
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata: { name: podinfo, namespace: env-a }
spec:
  interval: 5m
  chart:
    spec:
      chart: podinfo
      version: "6.x"
      sourceRef: { kind: HelmRepository, name: podinfo-helm, namespace: flux-system }
  values:
    replicaCount: 2
  install: { remediation: { retries: 2 } }
  upgrade: { remediation: { retries: 2, remediateLastFailure: true } }
EOF
sleep 90
flux -n env-a get helmreleases

echo ""
echo "=== 진짜 Helm 릴리스가 있는가요? (15의 릴리스 Secret) ==="
kubectl -n env-a get secret -l owner=helm
helm -n env-a history podinfo 2>/dev/null || echo "(helm CLI로도 보입니다)"
```

예상: `sh.helm.release.v1.podinfo.v1` Secret 존재, `helm history` 동작. ✅ **Flux는 Helm의 상태 기계를 살립니다**(theory §3) — 15에서 본 "두 진실의 긴장"에 대한 ArgoCD와 다른 답입니다.

## Step 6. 자동 교정 — remediation

```bash
# 잘못된 values로 업그레이드 → 실패 → 자동 롤백?
kubectl -n env-a patch helmrelease podinfo --type merge \
  -p '{"spec":{"values":{"replicaCount":2,"image":{"repository":"does-not-exist/nope"}}}}'
sleep 120
flux -n env-a get helmreleases
kubectl -n env-a get events --sort-by=.lastTimestamp | grep -i helmrelease | tail -4
helm -n env-a history podinfo 2>/dev/null | tail -3
```

예상: 업그레이드 실패 → 재시도 → `remediateLastFailure`로 이전 릴리스로 롤백. ✅ ArgoCD에는 없는(자체 방식이 다른) 내장 자동 교정입니다.

```bash
kubectl -n env-a patch helmrelease podinfo --type merge -p '{"spec":{"values":{"replicaCount":2}}}' >/dev/null
```

## Step 7. 조합의 확장 — 왜 다른 프로젝트가 Flux 위에 짓나

```bash
cat <<'EOF'
GitOps Toolkit이 라이브러리인 이유:
  - 각 컨트롤러가 독립 CRD·독립 프로세스 → 필요한 것만 설치(--components)
  - Source 추상(Git/Helm/OCI/Bucket)이 통일되어, 새 소비자를 만들기 쉽습니다
  - Flagger(Progressive Delivery)가 이 위에 지어졌고, 여러 플랫폼이 Flux를 내장

★ 08의 "오퍼레이터는 사다리를 관통하는 확장 문법"의 극단적 실천:
  Flux 자체가 CRD의 조합이고, 남이 그 조합에 부품을 끼울 수 있습니다
EOF
kubectl get crd | grep toolkit.fluxcd.io | wc -l
echo "→ 이 CRD들이 곧 공개 API다"
```

## Step 8. 산출물

```markdown
# Flux의 조합 문법 (오늘 확인)
- source-controller: GitRepository/HelmRepository/OCIRepository → 아티팩트(공유 가능)
- kustomize-controller: Kustomization — path·prune·healthChecks·dependsOn·interval
- helm-controller: HelmRelease — 진짜 Helm 릴리스(history·rollback·훅) + remediation
- 한 소스를 여러 적용이 참조 (ArgoCD는 Application마다 소스)
- 순서는 dependsOn(CR 필드), 상태는 CR status(UI 대신 flux get)
```

## 정리

lab-02에서 계속. 클러스터 유지.
