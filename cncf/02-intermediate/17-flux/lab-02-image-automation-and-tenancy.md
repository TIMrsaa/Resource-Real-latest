# Lab 02 — 이미지 자동화와 멀티테넌시: pull 루프의 완성

레지스트리 → Git 커밋 → 클러스터의 완전 pull 루프를 만들고, SA 임퍼소네이션으로 테넌트 경계를 세웁니다.

전제: lab-01의 클러스터(kind: flux), gh CLI(이미지 자동화용 Git 쓰기 권한).

## Step 1. 이미지 자동화 컨트롤러 추가

```bash
flux install --components-extra=image-reflector-controller,image-automation-controller
kubectl -n flux-system get deploy | grep image
kubectl get crd | grep image.toolkit
```

## Step 2. 레지스트리 스캔 — ImageRepository

```bash
kubectl apply -f - <<'EOF'
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata: { name: podinfo, namespace: flux-system }
spec:
  image: ghcr.io/stefanprodan/podinfo
  interval: 2m
EOF
sleep 40
kubectl -n flux-system get imagerepository podinfo
kubectl -n flux-system get imagerepository podinfo -o jsonpath='{.status.lastScanResult.tagCount}'; echo " 개의 태그를 발견"
```

✅ 레지스트리의 **태그 목록**을 스캔했습니다(이미지를 pull하는 것이 아닙니다 — 메타데이터만).

## Step 3. 정책으로 태그 선택 — ImagePolicy

```bash
kubectl apply -f - <<'EOF'
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata: { name: podinfo-policy, namespace: flux-system }
spec:
  imageRepositoryRef: { name: podinfo }
  policy:
    semver: { range: ">=6.0.0 <7.0.0" }     # ★ 정책이 안전의 핵심
EOF
sleep 20
kubectl -n flux-system get imagepolicy podinfo-policy -o jsonpath='{.status.latestImage}'; echo
```

예상: `ghcr.io/stefanprodan/podinfo:6.x.y`. ✅ **정책이 태그를 고릅니다** — 여기가 안전 장치입니다:

```bash
cat <<'EOF'
정책 종류와 위험:
  semver: {range: ">=6.0.0 <7.0.0"}   ✅ 메이저 고정, 안전
  numerical: {order: asc}              ⚠️ 타임스탬프 태그 등 — 규칙이 명확해야
  alphabetical: {order: asc}           ⚠️ "latest"가 뽑힐 수 있습니다
  + filterTags: {pattern: "^main-[a-f0-9]+-(?P<ts>.*)", extract: "$ts"}
     → 브랜치·커밋 태그에서 정렬 키 추출 (프로덕션 패턴)

★ 느슨한 정책 = 원치 않는 이미지가 자동으로 프로덕션에 (cicd 04의 태그 규율이 여기서도)
EOF
```

## Step 4. Git에 써넣기 — ImageUpdateAutomation (개념 + 안전 패턴)

```bash
cat <<'EOF'
[매니페스트에 마커를 남깁니다]
  image: ghcr.io/stefanprodan/podinfo:6.5.0 # {"$imagepolicy": "flux-system:podinfo-policy"}

[ImageUpdateAutomation]
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageUpdateAutomation
metadata: { name: podinfo-auto, namespace: flux-system }
spec:
  interval: 5m
  sourceRef: { kind: GitRepository, name: my-gitops }
  git:
    checkout: { ref: { branch: main } }
    commit:
      author: { email: flux@example.com, name: fluxbot }
      messageTemplate: "chore: update image to {{range .Updated.Images}}{{println .}}{{end}}"
    push:
      branch: image-updates          # ★ 안전: main에 직접 커밋하지 말고 별도 브랜치
  update: { path: ./apps, strategy: Setters }

★ 그리고 그 브랜치로 PR을 자동 생성(GitHub Action)해 리뷰를 거치게 합니다
   자동 커밋이 main에 직접 들어가면 리뷰 없는 배포가 됩니다 (cicd 24의 승인 게이트가 증발)
EOF
```

✅ **완전한 pull 루프**: CI는 레지스트리까지만 → Flux가 태그를 감지 → Git에 커밋 → Kustomization이 적용. cicd 14의 "push→pull 역전"이 이미지 층까지 내려온 형태입니다.

## Step 5. 멀티테넌시 — SA 임퍼소네이션

```bash
# 테넌트 네임스페이스와 제한된 SA
kubectl create ns team-a
kubectl -n team-a create sa reconciler
kubectl -n team-a create role deployer \
  --verb=create,update,patch,delete,get,list,watch \
  --resource=deployments,services,configmaps,pods
kubectl -n team-a create rolebinding reconciler-deployer \
  --role=deployer --serviceaccount=team-a:reconciler

# 이 SA의 권한으로만 적용하는 Kustomization
kubectl apply -f - <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata: { name: podinfo, namespace: team-a }
spec: { url: https://github.com/stefanprodan/podinfo, ref: { branch: master }, interval: 5m }
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: team-a-app, namespace: team-a }
spec:
  interval: 5m
  path: ./kustomize
  prune: true
  sourceRef: { kind: GitRepository, name: podinfo }
  serviceAccountName: reconciler        # ★ 이 SA의 RBAC를 넘을 수 없습니다
  targetNamespace: team-a
EOF
sleep 60
flux -n team-a get kustomizations
kubectl -n team-a get deploy
```

## Step 6. 경계 검증 — 권한을 넘는 배포는 거부됩니다

```bash
# team-a의 SA는 ClusterRole 생성 권한이 없습니다 → 그런 매니페스트를 넣으면?
cat <<'EOF'
실험 방법(실제 Git 저장소가 필요):
  team-a의 저장소에 ClusterRole 매니페스트를 추가하고 sync를 기다립니다
  → Kustomization status: "clusterroles.rbac.authorization.k8s.io is forbidden:
     User system:serviceaccount:team-a:reconciler cannot create..."

★ 경계를 지키는 것은 Flux가 아니라 K8s RBAC입니다 (theory §5)
  ArgoCD: 중앙 서버가 AppProject·RBAC로 판단 (16)
  Flux:   K8s API 서버가 SA의 RBAC로 판단
  → "K8s RBAC를 이미 신뢰하고 운영한다"면 Flux 모델이 자연스럽습니다

필수 설정: kustomize-controller에 --no-cross-namespace-refs=true
  (team-a의 Kustomization이 다른 네임스페이스의 Source를 참조하지 못하게)
EOF

kubectl -n flux-system get deploy kustomize-controller -o yaml | grep -A5 "args:" | head -8
```

## Step 7. 알림과 웹훅 — notification-controller

```bash
cat <<'EOF'
[out] 적용 결과를 Slack·GitHub commit status로
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata: { name: slack }
spec: { type: slack, secretRef: { name: slack-url } }
---
kind: Alert
spec:
  providerRef: { name: slack }
  eventSeverity: error
  eventSources: [{ kind: Kustomization, name: "*" }]

[in] GitHub 웹훅으로 즉시 reconcile (폴링 대기 제거 — 16의 webhook과 같은 이유)
kind: Receiver
spec:
  type: github
  events: [ping, push]
  resources: [{ kind: GitRepository, name: podinfo }]
  secretRef: { name: webhook-token }
EOF
```

## Step 8. 산출물 — Flux 운영 카드 + 선택 기준

```markdown
# Flux 운영
- 컨트롤러는 필요한 것만 설치(--components / --components-extra)
- 소스 공유: GitRepository 하나 → Kustomization 여럿(주기·경로·의존성 각자)
- 순서: dependsOn / 헬스: healthChecks / 정리: prune
- Helm: HelmRelease가 진짜 릴리스 — remediation으로 자동 롤백
- 이미지 자동화: 정책(semver 권장) + **별도 브랜치 + PR**(리뷰 유지)
- 테넌시: 네임스페이스 CR + serviceAccountName 임퍼소네이션 + --no-cross-namespace-refs
- 웹훅 Receiver로 즉시 reconcile

# 선택 기준 (48의 예고)
| 조직의 성질 | 권장 |
|-------------|------|
| 개발자에게 배포 UI 제공이 중요 | ArgoCD |
| 중앙 거버넌스·다중 클러스터 단일 뷰 | ArgoCD |
| K8s RBAC·네임스페이스로 테넌시 운영 중 | Flux |
| Helm 릴리스 상태 기계 유지 필요 | Flux |
| 플랫폼에 GitOps를 '내장'하려 함 | Flux(툴킷) |
★ 둘 다 Graduated. "우리 조직의 성질과 맞는가"가 옳은 질문
```

## 정리

```bash
bash cleanup.sh
```
