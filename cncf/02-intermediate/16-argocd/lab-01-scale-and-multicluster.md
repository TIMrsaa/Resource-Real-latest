# Lab 01 — 부하의 해부와 두 번째 클러스터

컴포넌트별 부하를 지표로 보고, 대상 클러스터를 하나 더 붙여 멀티클러스터의 실체(자격증명·watch)를 확인합니다.

전제: kind, kubectl, helm. 메모리 8GB+.

## Step 1. 허브 클러스터와 ArgoCD

```bash
kind create cluster --name hub -q
kubectl config use-context kind-hub

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set configs.params."server\.insecure"=true \
  --set controller.metrics.enabled=true \
  --set repoServer.metrics.enabled=true >/dev/null
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s 2>/dev/null || \
  kubectl -n argocd rollout status deploy/argocd-application-controller --timeout=300s
```

## Step 2. 컴포넌트 지도 확인

```bash
kubectl -n argocd get pods
echo ""
echo "=== 각자의 역할 (theory §1) ==="
cat <<'EOF'
  argocd-repo-server            Git fetch + helm template/kustomize build (렌더링 공장)
  argocd-application-controller 클러스터 watch + diff + sync (감독관)
  argocd-redis                  캐시 (렌더 결과·리소스 트리)
  argocd-server                 API/UI
  argocd-applicationset-controller  Application을 생성하는 컨트롤러
EOF
```

## Step 3. 앱을 여러 개 만들어 부하 관찰

```bash
for i in $(seq 1 8); do
kubectl apply -f - <<EOF >/dev/null
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: guestbook-$i, namespace: argocd }
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination: { server: https://kubernetes.default.svc, namespace: ns-$i }
  syncPolicy: { automated: {}, syncOptions: [CreateNamespace=true] }
EOF
done
sleep 60
kubectl -n argocd get app | head -10
```

## Step 4. 부하 지표 — 어디가 바쁜가

```bash
CTRL=$(kubectl -n argocd get pod -l app.kubernetes.io/name=argocd-application-controller -o name | head -1)
REPO=$(kubectl -n argocd get pod -l app.kubernetes.io/name=argocd-repo-server -o name | head -1)

echo "=== application-controller 메트릭 (일부) ==="
kubectl -n argocd exec $CTRL -- wget -qO- http://localhost:8082/metrics 2>/dev/null | \
  grep -E "^argocd_app_reconcile_bucket|^argocd_cluster_api_resource_objects|^argocd_app_info" | head -5

echo ""
echo "=== repo-server: 렌더링 요청 ==="
kubectl -n argocd exec $REPO -- wget -qO- http://localhost:8084/metrics 2>/dev/null | \
  grep -E "argocd_repo_" | head -5

echo ""
echo "=== 메모리 사용 ==="
kubectl -n argocd top pod 2>/dev/null || echo "(metrics-server 없음 — kubectl describe로 확인)"
```

✅ `argocd_cluster_api_resource_objects`는 **컨트롤러가 캐시하고 있는 오브젝트 수** — 이것이 메모리를 지배합니다(theory §1). 앱이 아니라 **클러스터의 리소스 총량**이 controller 메모리를 정한다는 것이 핵심 통찰.

## Step 5. 감춰진 부하 — 대상 클러스터 API를 보라

```bash
echo "=== ArgoCD가 watch 중인 리소스 종류 ==="
kubectl -n argocd exec $CTRL -- wget -qO- http://localhost:8082/metrics 2>/dev/null | \
  grep "argocd_cluster_api_resources" | head -3

cat <<'EOF'

ArgoCD는 대상 클러스터의 (거의) 모든 리소스 종류를 watch합니다.
  → 클러스터에 Cilium(CiliumEndpoint 수만 개)·Event 등이 많으면 controller 메모리 폭발
  → 그리고 대상 클러스터 API 서버도 그 watch를 응대하느라 바쁩니다

방어: argocd-cm 의 resource.exclusions
EOF

kubectl -n argocd patch cm argocd-cm --type merge -p '{"data":{"resource.exclusions":"- apiGroups:\n  - \"\"\n  kinds:\n  - Event\n  - EndpointSlice\n  clusters:\n  - \"*\"\n"}}'
kubectl -n argocd rollout restart statefulset/argocd-application-controller 2>/dev/null || \
  kubectl -n argocd rollout restart deploy/argocd-application-controller
echo "→ Event·EndpointSlice를 watch에서 제외 (controller 메모리·대상 API 부하 감소)"
```

## Step 6. 두 번째 클러스터 등록 — 자격증명이 어디로 가는가

```bash
kind create cluster --name spoke -q
kubectl config use-context kind-spoke
kubectl create sa argocd-manager -n kube-system
kubectl create clusterrolebinding argocd-manager --clusterrole=cluster-admin \
  --serviceaccount=kube-system:argocd-manager

# 토큰 생성
TOKEN=$(kubectl create token argocd-manager -n kube-system --duration=8760h)
SPOKE_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# 허브에서 등록 (Secret으로!)
kubectl config use-context kind-hub
kubectl -n argocd create secret generic cluster-spoke \
  --from-literal=name=spoke \
  --from-literal=server="$SPOKE_URL" \
  --from-literal=config="{\"bearerToken\":\"$TOKEN\",\"tlsClientConfig\":{\"insecure\":false,\"caData\":\"$CA\"}}" \
  >/dev/null
kubectl -n argocd label secret cluster-spoke argocd.argoproj.io/secret-type=cluster

kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=cluster
```

⚠️ **여기가 핵심 관찰**: 대상 클러스터의 cluster-admin 토큰이 **허브의 Secret에 저장**됩니다.

```bash
cat <<'EOF'
보안 함의 (theory §3, 07의 시간선):
  ArgoCD 침해 = 등록된 모든 클러스터의 cluster-admin 권한 침해
  → 방어: ① ArgoCD 네임스페이스의 접근 통제(RBAC·NetworkPolicy)
          ② 대상 클러스터 SA의 권한 최소화 (cluster-admin 말고 필요한 것만)
          ③ 자격증명 순환(cicd 22) — 토큰 TTL과 갱신 절차
          ④ 클러스터별 ArgoCD(형태 C)로 폭발 반경 축소 검토
  ★ "중앙집중의 편의"에는 이 대가가 붙습니다
EOF
```

## Step 7. spoke에 배포 — 멀티클러스터 실증

```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: guestbook-spoke, namespace: argocd }
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination: { server: "$SPOKE_URL", namespace: remote }
  syncPolicy: { automated: {}, syncOptions: [CreateNamespace=true] }
EOF
sleep 60
kubectl -n argocd get app guestbook-spoke -o jsonpath='{.status.sync.status}/{.status.health.status}'; echo

kubectl config use-context kind-spoke
kubectl -n remote get deploy 2>/dev/null && echo "✅ 허브의 ArgoCD가 spoke에 배포했다"
kubectl config use-context kind-hub
```

## Step 8. 산출물 — 규모 운영 카드

```markdown
# ArgoCD 규모 운영
| 증상 | 원인 | 손잡이 |
|------|------|--------|
| sync 느림 | repo-server 렌더링 대기 | replicas↑, --parallelismlimit, 캐시 |
| controller OOM | 클러스터 리소스 캐시 | resource.exclusions, 샤딩 |
| OutOfSync 감지 지연 | reconcile 주기·리스트 부하 | webhook 필수, timeout.reconciliation |
| 대상 API 서버 부하 | ArgoCD의 watch | resource.exclusions |
| 전체 급락 | redis 다운 | redis-ha |

# 멀티클러스터 결정
- 자격증명이 허브에 집중됨 = ArgoCD 침해가 전 클러스터 침해
- 대상 SA는 cluster-admin이 아니라 최소 권한으로
- 폭발 반경이 중요하면 클러스터별 ArgoCD(형태 C) 검토
```

## 정리

lab-02에서 계속. 두 클러스터 유지.
