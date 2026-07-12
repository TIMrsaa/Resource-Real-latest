# Lab 01 — reconcile 루프를 눈으로: drift가 교정됩니다

ArgoCD를 설치하고 Application을 만든 뒤, **드리프트를 일부러 만들어 컨트롤러가 교정하는 것**을 관찰합니다. push CD에서는 불가능했던 자동 조정을 실측합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. ArgoCD 설치

```bash
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
kubectl -n argocd rollout status deploy/argocd-application-controller --timeout=120s 2>/dev/null || \
  kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=120s

# 초기 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

✅ 설치된 컴포넌트 중 **application-controller**가 reconcile 루프의 심장입니다(theory §2, k8s 30 패턴).

## Step 2. config repo — 배포 매니페스트 (app 코드와 분리)

```bash
mkdir -p ~/ci-lab/gitops/apps/demo && cd ~/ci-lab/gitops
git init -q && git config user.email l@e.com && git config user.name L

cat > apps/demo/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: demo, namespace: gitops-demo }
spec:
  replicas: 2                    # ★ 이 값이 git의 "진실"
  selector: { matchLabels: { app: demo } }
  template:
    metadata: { labels: { app: demo } }
    spec:
      containers:
      - name: app
        image: ghcr.io/stefanprodan/podinfo:6.7.1    # (04: 실전은 다이제스트)
        ports: [{ containerPort: 9898 }]
EOF
cat > apps/demo/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata: { name: gitops-demo }
EOF

git add -A && git commit -qm "add demo app"
gh repo create cicd-lab-gitops --public --source=. --push >/dev/null
REPO_URL=$(gh repo view --json url -q .url)
echo "config repo: $REPO_URL"
```

> **app repo와 config repo 분리**(theory §6): 여기는 매니페스트만. 앱 코드는 별도 저장소에서 CI가 이미지를 빌드하고 이 config repo를 업데이트합니다.

## Step 3. Application — "이 git을 클러스터에 맞춰라"

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $REPO_URL
    path: apps/demo
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: gitops-demo
  syncPolicy:
    automated:
      selfHeal: true       # ★ 드리프트 교정
      prune: true          # ★ git 삭제 반영
    syncOptions: [ CreateNamespace=true ]
EOF

sleep 30
kubectl -n argocd get application demo -o jsonpath='{.status.sync.status} / {.status.health.status}'; echo
kubectl -n gitops-demo get deploy,pods
```

예상: `Synced / Healthy`, demo가 2 replicas로. ✅ **파이프라인 없이** 클러스터가 git을 당겨와 배포했습니다 — pull CD.

## Step 4. 드리프트 실험 ① — kubectl로 몰래 수정

push CD에서는 아무도 모를 수동 변경을 해봅니다:

```bash
kubectl -n gitops-demo scale deploy demo --replicas=5
kubectl -n gitops-demo get deploy demo -o jsonpath='{.spec.replicas}'; echo   # 5

# ArgoCD가 감지·교정하는 것을 관찰
echo "selfHeal 관찰 (최대 ~1분)..."
for i in $(seq 1 12); do
  R=$(kubectl -n gitops-demo get deploy demo -o jsonpath='{.spec.replicas}')
  S=$(kubectl -n argocd get application demo -o jsonpath='{.status.sync.status}')
  echo "  replicas=$R sync=$S"
  [ "$R" = "2" ] && { echo "✅ git(2)으로 자동 교정됨!"; break; }
  sleep 5
done
```

예상: replicas가 5 → **다시 2**로 돌아옵니다. ✅ **selfHeal이 드리프트를 교정했습니다**(theory §3). "kubectl로 고쳤는데 원복됐다"의 정체 — eks 11의 애드온 SSA와 같은 사상(git이 진실).

## Step 5. 드리프트 실험 ② — git이 진실임을 증명

이번엔 git을 바꾸면?

```bash
sed -i 's/replicas: 2/replicas: 4/' apps/demo/deployment.yaml
git commit -qam "scale to 4" && git push -q
echo "git 변경 → ArgoCD가 감지·적용 관찰..."
for i in $(seq 1 24); do
  R=$(kubectl -n gitops-demo get deploy demo -o jsonpath='{.spec.replicas}')
  echo "  replicas=$R"
  [ "$R" = "4" ] && { echo "✅ git(4)이 클러스터에 반영됨!"; break; }
  sleep 5
done
```

✅ **git을 바꾸니 클러스터가 따라왔습니다.** 대조: kubectl 변경은 원복(Step 4), git 변경은 반영(Step 5) — **git만이 진실입니다**(theory §1). 이것이 감사(누가 언제 무엇을 바꿨나 = git log)와 롤백(git revert)을 주는 이유.

## Step 6. 롤백 = git revert (k8s 39)

```bash
git revert --no-edit HEAD          # scale to 4를 되돌림
git push -q
sleep 30
kubectl -n gitops-demo get deploy demo -o jsonpath='{.spec.replicas}'; echo   # 2로 롤백
kubectl -n argocd get application demo -o jsonpath='{.status.history[-1].revision}' | head -c 8; echo
```

✅ **롤백이 git revert 하나**입니다(01의 "30분 안에 되돌릴 수 있는가"의 가장 우아한 답). 그리고 그 롤백조차 git에 기록되어 감사됩니다.

## Step 7. 두 상태 축 확인 (theory §2)

```bash
# 앱을 일부러 죽여 Health와 Sync를 분리
kubectl -n gitops-demo set image deploy/demo app=ghcr.io/stefanprodan/podinfo:nonexistent-tag
sleep 20
kubectl -n argocd get application demo -o jsonpath='{.status.sync.status} / {.status.health.status}'; echo
```

예상: selfHeal이 git 이미지로 되돌리거나, 잠시 `Synced / Progressing`(또는 Degraded)을 보입니다. ✅ **Sync(git과 같은가)와 Health(정상인가)는 다른 축** — 진단 시 어느 축의 문제인지 먼저 구분합니다.

## 정리

Application과 config repo는 lab-02에서 계속 사용.
