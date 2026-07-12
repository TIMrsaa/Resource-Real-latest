# Lab 01 — ArgoCD 설치와 첫 동기화

## Step 1. 설치

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
kubectl get pods -n argocd
```

예상: repo-server, application-controller(StatefulSet), api-server, redis 등이 Running — theory §2의 세 部品 실물.

## Step 2. CLI와 UI 접속

```bash
# CLI 설치 (WSL2)
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && sudo mv argocd /usr/local/bin/

# 초기 admin 비밀번호
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "admin / $PASS"

# 포트포워드로 접속 (LoadBalancer 비용 절약)
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
sleep 2
argocd login localhost:8080 --username admin --password "$PASS" --insecure
```

브라우저: https://localhost:8080 (자체 서명 인증서 경고는 통과) — 빈 대시보드가 보입니다.

## Step 3. 첫 Application — 공개 예제 리포로

자기 리포가 없어도 되도록 공식 예제 리포(guestbook)를 씁니다:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    syncOptions: [CreateNamespace=true]
    # automated는 아직 안 켭니다 — 수동 동기화부터 (theory §5의 점진 도입)
EOF
kubectl get application -n argocd
```

예상:
```
NAME        SYNC STATUS   HEALTH STATUS
guestbook   OutOfSync     Missing
```

✅ **OutOfSync + Missing**: "Git엔 있는데 클러스터엔 없다" — ArgoCD가 diff를 인지했지만 아직 손대지 않았습니다(수동 모드).

## Step 4. diff 보고 동기화

```bash
argocd app diff guestbook | head -20      # 무엇이 적용될지 미리보기
argocd app sync guestbook                  # 동기화 실행
argocd app get guestbook
```

예상:
```
NAME        SYNC STATUS   HEALTH STATUS
guestbook   Synced        Healthy        (Progressing을 거쳐)
kubectl get all -n guestbook               # deployment/service가 생겼습니다
```

✅ **우리는 kubectl apply를 치지 않았습니다** — Git 경로를 가리켰을 뿐. UI에서 guestbook 앱을 열면 리소스 트리(Application→Deployment→RS→Pod)가 시각화됩니다: ownerReference(모듈 24)의 지도입니다.

## Step 5. "새 커밋 배포" 시뮬레이션

남의 리포라 커밋은 못 하지만, **targetRevision을 과거 커밋으로 바꿔** "Git이 변하면 따라간다"를 봅니다:

```bash
# 예제 리포의 이전 커밋 하나 (kustomize 이전 시절 등 아무거나)
argocd app set guestbook --revision 53e28ff
argocd app get guestbook | grep -E "Revision|Sync Status"    # OutOfSync — Git(그 시점)과 다름
argocd app sync guestbook
argocd app set guestbook --revision HEAD && argocd app sync guestbook   # 원복
```

✅ **배포 = "가리키는 리비전의 변경"**이라는 GitOps의 본질. 실무에선 이 "가리킴 변경"이 git push 한 번입니다.

## Step 6. 상태 2축 체험 — Synced인데 Degraded

```bash
# Git대로인데 안 뜨는 상황: 이미지를 깨뜨림 (클러스터 직접 변경 = 의도적 드리프트이기도)
kubectl set image deploy/guestbook-ui guestbook-ui=nonexistent:v9 -n guestbook
sleep 10
argocd app get guestbook | grep -E "Sync Status|Health Status"
```

예상: `OutOfSync` + `Degraded` — 드리프트(수동 변경)와 비건강(ImagePullBackOff)을 **동시에, 각각** 감지했습니다.

```bash
argocd app sync guestbook    # Git대로 원복 → 다시 Synced/Healthy
```

✅ 모듈 38이라면 describe/이벤트로 추적할 일을, ArgoCD 대시보드가 첫 화면에서 보여줍니다 — GitOps는 운영 가시성 도구이기도 합니다.

## 정리

guestbook과 ArgoCD는 lab-02에서 계속.
