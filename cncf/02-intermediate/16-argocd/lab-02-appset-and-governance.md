# Lab 02 — ApplicationSet의 힘과 위험, 그리고 멀티팀 경계

앱을 만드는 앱을 다루고(그 위험까지), AppProject·RBAC로 50개 팀이 공존할 수 있는 경계를 세웁니다.

전제: lab-01의 hub·spoke 클러스터, ArgoCD 설치됨.

## Step 1. ApplicationSet — clusters 생성기

```bash
kubectl config use-context kind-hub

# 클러스터 Secret에 라벨을 달아 선택 가능하게
kubectl -n argocd label secret cluster-spoke env=prod --overwrite
# in-cluster(허브 자신)도 대상에 넣으려면 등록 필요 — 여기서는 spoke만 사용

kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: { name: guestbook-all-clusters, namespace: argocd }
spec:
  generators:
    - clusters:
        selector: { matchLabels: { env: prod } }
  template:
    metadata: { name: "guestbook-{{name}}" }
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps.git
        targetRevision: HEAD
        path: guestbook
      destination: { server: "{{server}}", namespace: appset-demo }
      syncPolicy: { automated: {}, syncOptions: [CreateNamespace=true] }
EOF
sleep 30
kubectl -n argocd get app | grep guestbook-spoke || kubectl -n argocd get app
```

✅ 클러스터 라벨 하나로 Application이 **자동 생성**됐습니다. 새 클러스터를 등록하고 `env=prod`를 달면 앱이 저절로 생깁니다(그것이 요점).

## Step 2. 위험 실험 — 라벨 하나가 앱을 삭제합니다

```bash
echo "현재 ApplicationSet이 만든 앱:"
kubectl -n argocd get app -l argocd.argoproj.io/instance 2>/dev/null | head -3
kubectl -n argocd get app | grep -c guestbook || true

# 라벨을 떼면?
kubectl -n argocd label secret cluster-spoke env-
sleep 20
echo ""
echo "라벨 제거 후:"
kubectl -n argocd get app | grep guestbook-spoke || echo "  → Application이 사라졌습니다!"

kubectl config use-context kind-spoke
kubectl -n appset-demo get deploy 2>/dev/null || echo "  → 그리고 워크로드도 삭제됐다 ⚠️"
kubectl config use-context kind-hub
```

예상: Application 삭제 → **워크로드까지 삭제**. ✅ theory §4의 위험: 생성기 파라미터(여기선 라벨) 변경이 수백 앱을 지울 수 있습니다.

## Step 3. 방어 — 삭제를 막는 두 장치

```bash
kubectl -n argocd label secret cluster-spoke env=prod --overwrite   # 복구

kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: { name: guestbook-all-clusters, namespace: argocd }
spec:
  generators:
    - clusters: { selector: { matchLabels: { env: prod } } }
  # ★ 방어 ①: 생성·갱신만 허용, 삭제 금지
  syncPolicy:
    applicationsSync: create-update
    preserveResourcesOnDeletion: true      # ★ 방어 ②: 앱이 지워져도 워크로드는 남김
  template:
    metadata: { name: "guestbook-{{name}}" }
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps.git
        targetRevision: HEAD
        path: guestbook
      destination: { server: "{{server}}", namespace: appset-demo }
      syncPolicy: { automated: {}, syncOptions: [CreateNamespace=true] }
EOF
sleep 20

kubectl -n argocd label secret cluster-spoke env-      # 다시 라벨 제거
sleep 20
kubectl -n argocd get app | grep guestbook-spoke && echo "  → 방어 ①: Application이 살아있다"
kubectl config use-context kind-spoke
kubectl -n appset-demo get deploy >/dev/null 2>&1 && echo "  → 방어 ②: 워크로드도 안전"
kubectl config use-context kind-hub
kubectl -n argocd label secret cluster-spoke env=prod --overwrite
```

✅ 프로덕션 ApplicationSet은 이 두 옵션 없이 쓰지 마세요. 그리고 변경은 항상 PR + `--dry-run`으로.

## Step 4. git 디렉터리 생성기 — 모노레포와 만나는 지점

```bash
cat <<'EOF'
[cicd 20의 affected + ApplicationSet]
generators:
  - git:
      repoURL: https://github.com/org/gitops
      revision: HEAD
      directories: [{ path: "apps/*" }]        # 디렉터리 하나 = 앱 하나
template:
  metadata: { name: "{{path.basename}}" }
  spec: { source: { path: "{{path}}" } }

→ CI가 affected 서비스의 매니페스트만 갱신 → 그 앱만 OutOfSync → 그 앱만 sync
  "저장소는 하나, 배포 단위는 그래프가 정한다" (cicd 20의 결론이 여기서 구현됩니다)

주의: 디렉터리를 지우면 앱이 삭제됩니다 → preserveResourcesOnDeletion 검토
EOF
```

## Step 5. AppProject — 팀 경계의 1층

```bash
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: { name: team-a, namespace: argocd }
spec:
  description: "Team A only"
  sourceRepos:
    - "https://github.com/argoproj/argocd-example-apps.git"   # 이 저장소만
  destinations:
    - { server: "https://kubernetes.default.svc", namespace: "team-a-*" }  # 이 네임스페이스만
  clusterResourceWhitelist: []                    # 클러스터 스코프 리소스 생성 금지
  namespaceResourceBlacklist:
    - { group: "", kind: "ResourceQuota" }
    - { group: "", kind: "LimitRange" }
EOF

# 위반 시도: 허용되지 않은 네임스페이스
kubectl apply -f - <<'EOF' 2>&1 | tail -2
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: bad-app, namespace: argocd }
spec:
  project: team-a
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination: { server: https://kubernetes.default.svc, namespace: kube-system }
EOF
sleep 10
kubectl -n argocd get app bad-app -o jsonpath='{.status.conditions[*].message}' 2>/dev/null | head -c 200; echo
kubectl -n argocd delete app bad-app --ignore-not-found >/dev/null
```

예상: `destination ... not permitted in project team-a` — ✅ **AppProject가 목적지·소스·리소스 종류를 좁힙니다**(cicd 24의 "강제는 좁게"의 배달 층 구현).

## Step 6. RBAC — 팀 경계의 2층 (행위 제한)

```bash
kubectl -n argocd patch cm argocd-rbac-cm --type merge -p '{"data":{
  "policy.default":"role:readonly",
  "policy.csv":"p, role:dev, applications, get, */*, allow\np, role:dev, applications, sync, dev-*/*, allow\np, role:dev, applications, sync, prod-*/*, deny\np, role:dev, applications, delete, */*, deny\ng, org:developers, role:dev\n"
}}'

cat <<'EOF'
RBAC의 축 (theory §5):
  주체(g): SSO 그룹 → 역할
  객체:    applications, clusters, repositories, projects...
  행위:    get, create, update, delete, sync, override, action/*
  범위:    <project>/<application>

이 예시가 강제하는 것:
  개발자는 모든 앱을 볼 수 있지만
  dev-* 프로젝트만 sync할 수 있고
  prod-* sync와 모든 delete는 금지
  기본은 readonly

★ AppProject(무엇을 어디에) + RBAC(누가 무엇을) = 두 층이 함께여야 경계가 섭니다
EOF
```

## Step 7. app-of-apps — 부트스트랩 패턴

```bash
cat <<'EOF'
루트 Application 하나가 Git의 apps/ 디렉터리를 가리키고,
그 안의 각 YAML이 또 다른 Application입니다:

  apps/
  ├── monitoring.yaml     (Application → prometheus 차트)
  ├── ingress.yaml        (Application → ingress-nginx)
  └── team-a.yaml         (Application → team-a의 앱들)

효과: 새 클러스터에 루트 앱 하나만 적용하면 전부 배포됩니다 (부트스트랩)
     ArgoCD 자신도 이렇게 self-manage 가능 (자기 매니페스트를 Git에서)

ApplicationSet과의 차이:
  app-of-apps: 정적 목록(Git 파일들) — 명시적, 리뷰 쉬움
  ApplicationSet: 동적 생성(클러스터·디렉터리·PR) — 확장성, 삭제 위험
  둘을 함께 쓰기도 합니다 (루트는 app-of-apps, 팀 앱은 ApplicationSet)
EOF
```

## Step 8. 산출물

```markdown
# 조직 규모 ArgoCD 체크리스트
- [ ] resource.exclusions로 watch 범위 축소 (controller 메모리 + 대상 API 부하)
- [ ] webhook 설정 (폴링 의존 금지)
- [ ] repo-server 스케일·캐시, redis HA
- [ ] 샤딩(클러스터 수가 많으면)
- [ ] ApplicationSet: applicationsSync=create-update + preserveResourcesOnDeletion
- [ ] AppProject: 팀별 소스·목적지·리소스 화이트리스트
- [ ] RBAC: prod sync·delete 제한, 기본 readonly
- [ ] 대상 클러스터 SA는 cluster-admin 아닌 최소 권한 + 토큰 순환(cicd 22)
- [ ] 멀티클러스터 형태 결정(중앙집중/허브-스포크/클러스터별)과 폭발 반경 문서화
```

## 정리

```bash
bash cleanup.sh
```
