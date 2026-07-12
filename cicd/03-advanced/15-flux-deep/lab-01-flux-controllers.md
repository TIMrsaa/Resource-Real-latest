# Lab 01 — Flux 컨트롤러 조합을 ArgoCD와 나란히

Flux를 설치하고 GitRepository+Kustomization으로 앱을 배포하며, 14의 ArgoCD Application과 대조합니다. 같은 GitOps, 다른 구조.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. Flux CLI와 설치

```bash
# flux CLI 설치 (https://fluxcd.io/flux/installation/)
curl -s https://fluxcd.io/install.sh | sudo bash 2>/dev/null || \
  echo "수동 설치: https://github.com/fluxcd/flux2/releases"

flux check --pre    # 사전 요구사항 확인

# 설치 (GitOps 부트스트랩 없이 컴포넌트만 — 학습용)
flux install
kubectl -n flux-system get pods
```

예상: `source-controller`, `kustomize-controller`, `helm-controller`, `notification-controller` Pod들. ✅ **여러 작은 컨트롤러**(theory §1) — ArgoCD의 하나의 큰 앱과 대조되는 유닉스 철학.

## Step 2. config repo

```bash
mkdir -p ~/ci-lab/flux/apps/demo && cd ~/ci-lab/flux
git init -q && git config user.email l@e.com && git config user.name L
cat > apps/demo/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: demo, namespace: flux-demo }
spec:
  replicas: 2
  selector: { matchLabels: { app: demo } }
  template:
    metadata: { labels: { app: demo } }
    spec:
      containers:
      - name: app
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        ports: [{ containerPort: 9898 }]
EOF
cat > apps/demo/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata: { name: flux-demo }
EOF
git add -A && git commit -qm "add demo" 
gh repo create cicd-lab-flux --public --source=. --push >/dev/null
REPO_URL=$(gh repo view --json url -q .url)
```

## Step 3. GitRepository + Kustomization — source와 apply의 분리

14의 ArgoCD Application 하나가 Flux에서는 **두 리소스**로 나뉩니다(theory §2):

```bash
# ① source: "이 git을 가져와라"
flux create source git demo \
  --url=$REPO_URL --branch=main --interval=1m

# ② apply: "가져온 것의 이 경로를 적용해라"
flux create kustomization demo \
  --source=GitRepository/demo \
  --path="./apps/demo" \
  --prune=true \
  --interval=10m

sleep 30
flux get sources git
flux get kustomizations
kubectl -n flux-demo get deploy
```

예상: GitRepository가 Ready, Kustomization이 Applied, demo가 배포됨. ✅ **source(가져오기)와 apply(적용)가 분리**됐습니다 — 대조표:

```markdown
# 14 ArgoCD vs 15 Flux (같은 배포)
| | ArgoCD | Flux |
|---|---|---|
| 리소스 | Application 1개 | GitRepository + Kustomization |
| source | Application.spec.source | GitRepository (재사용 가능) |
| apply | Application.spec (통합) | Kustomization |
| prune | syncPolicy.automated.prune | Kustomization.spec.prune |
| UI | 내장 대시보드 | flux CLI (또는 별도 UI) |
```

## Step 4. drift 교정 — Flux도 같습니다

14와 같은 실험 — 개념이 이식됨을 확인:

```bash
kubectl -n flux-demo scale deploy demo --replicas=5
echo "Flux reconcile 관찰..."
flux reconcile kustomization demo    # 즉시 조정 트리거 (또는 interval 대기)
sleep 15
kubectl -n flux-demo get deploy demo -o jsonpath='{.spec.replicas}'; echo   # 2로 교정
```

✅ **drift 교정도 GitOps 원칙 그대로**(14와 동일). 도구가 달라도 reconcile·selfHeal·prune·git이 진실 — OpenGitOps 4원칙(theory §6)이 이식됩니다.

## Step 5. source 재사용 — Flux의 설계 이점

하나의 GitRepository를 여러 Kustomization이 공유:

```bash
mkdir -p apps/demo2
cp apps/demo/deployment.yaml apps/demo2/deployment.yaml
sed -i 's/name: demo/name: demo2/; s/flux-demo/flux-demo/' apps/demo2/deployment.yaml
git add -A && git commit -qm "add demo2" && git push -q

# 같은 source(demo)를 재사용, 다른 경로
flux create kustomization demo2 \
  --source=GitRepository/demo \
  --path="./apps/demo2" --prune=true --interval=10m
sleep 20
flux get kustomizations
kubectl -n flux-demo get deploy
```

✅ **하나의 git을 여러 Kustomization이 공유**합니다 — git을 한 번만 가져와 여러 앱에 적용(대역폭·부하 절감). ArgoCD는 Application마다 source를 갖는 것과 대조되는 Flux의 설계 선택.

## Step 6. 산출물

```markdown
# ArgoCD ↔ Flux 대조 (내가 확인한 것)
| 측면 | ArgoCD | Flux | 같은가요? |
|------|--------|------|--------|
| GitOps 원칙(선언/git/pull/reconcile) | ✓ | ✓ | 완전 동일 |
| drift 교정 | selfHeal | reconcile | 동일 개념 |
| prune | ✓ | ✓ | 동일 |
| 구조 | 1 앱+UI | 컨트롤러 조합 | 다름(철학) |
| source-apply | 통합 | 분리(재사용) | 다름(설계) |
| UI | 강력 | CLI/별도 | 다름 |
→ 원칙은 이식, 구조·철학이 다름 (12의 교훈 GitOps판)
```

## 정리

lab-02에서 이미지 자동화를 다룹니다.
