# Lab 02 — ApplicationSet fleet와 GitOps의 경계

fleet(eks 23)에 앱을 전개하고, GitOps가 정직하게 다뤄야 할 경계 세 가지(시크릿·이미지 업데이트·CI 접점)를 실습합니다.

전제: lab-01의 ArgoCD와 config repo(~/ci-lab/gitops).

## Step 1. ApplicationSet — 디렉터리마다 앱 (eks 23의 fleet)

```bash
cd ~/ci-lab/gitops
# 여러 앱 디렉터리 (fleet 대상)
for app in web api worker; do
  mkdir -p apps/$app
  cat > apps/$app/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: $app, namespace: gitops-fleet }
spec:
  replicas: 1
  selector: { matchLabels: { app: $app } }
  template:
    metadata: { labels: { app: $app } }
    spec:
      containers:
      - name: app
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        env: [{ name: PODINFO_UI_MESSAGE, value: "$app" }]
EOF
done
cat > apps/namespace.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata: { name: gitops-fleet }
EOF
git add -A && git commit -qm "add fleet apps" && git push -q
REPO_URL=$(gh repo view --json url -q .url)
```

```bash
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: { name: fleet, namespace: argocd }
spec:
  generators:
    - git:                        # git의 apps/* 디렉터리마다 Application 생성
        repoURL: $REPO_URL
        revision: main
        directories:
          - path: apps/*
  template:
    metadata: { name: 'fleet-{{path.basename}}' }
    spec:
      project: default
      source: { repoURL: $REPO_URL, path: '{{path}}', targetRevision: main }
      destination: { server: https://kubernetes.default.svc, namespace: gitops-fleet }
      syncPolicy:
        automated: { selfHeal: true, prune: true }
        syncOptions: [ CreateNamespace=true ]
EOF
sleep 40
kubectl -n argocd get applications
kubectl -n gitops-fleet get deploy
```

예상: `fleet-web`, `fleet-api`, `fleet-worker` Application이 자동 생성되고 각 Deployment가 배포. ✅ **하나의 ApplicationSet이 디렉터리 수만큼 앱을 전개**했습니다 — eks 23의 fleet 표준화가 CD로 실현. 새 앱은 `apps/새이름/` 디렉터리 추가 = 온보딩.

## Step 2. prune의 양날 — git 삭제가 클러스터 삭제

```bash
# git에서 worker 앱 디렉터리 제거
git rm -r apps/worker >/dev/null && git commit -qm "remove worker" && git push -q
sleep 40
kubectl -n argocd get applications | grep worker || echo "✅ fleet-worker Application 삭제됨"
kubectl -n gitops-fleet get deploy worker 2>&1 | tail -1   # NotFound (prune)
```

✅ **git에서 지우니 클러스터에서도 사라졌습니다**(prune). 이것이 "git이 진실"의 완성 — git에 없으면 클러스터에도 없습니다. 그러나 이것이 **양날**입니다:

```markdown
# prune의 위험과 안전벨트
- 위험: git 실수(잘못된 rm, 잘못된 머지)가 프로덕션 삭제
- 안전벨트:
  1. PR 리뷰 (02) — git 변경이 리뷰를 거침
  2. PrunePropagationPolicy, prune 확인 옵션
  3. 중요 리소스에 argocd.argoproj.io/sync-options: Prune=false
  4. app-of-apps 패턴에서 최상위는 수동 sync
```

## Step 3. 경계 ① — 시크릿을 git에 (평문 금지)

```bash
echo "❌ 절대 금지: Secret을 평문/base64로 git에 (25의 교훈: base64는 암호화 아님)"
cat <<'EOF'
# ✅ 방안 비교
## Sealed Secrets
   kubeseal로 공개키 암호화 → SealedSecret을 git에 → 클러스터의 controller가 복호화
   git에 있는 것은 암호문 (안전)

## External Secrets Operator (권장 — eks 25와 통합)
   git엔 ExternalSecret(참조만): "Secrets Manager의 myapp/db를 가져와라"
   실제 값은 AWS Secrets Manager (eks 25) — git엔 값이 없습니다
   apiVersion: external-secrets.io/v1
   kind: ExternalSecret
   spec:
     secretStoreRef: { name: aws-secrets }
     data: [{ secretKey: password, remoteRef: { key: myapp/db, property: password } }]

## SOPS + KMS/age
   파일을 암호화해 git에, ArgoCD 플러그인이 복호화
EOF
echo "핵심: 모든 것을 git에 두되, 시크릿의 '값'은 git 밖(참조만 git에)"
```

## Step 4. 경계 ② — 이미지 태그 업데이트 (CI-CD 접점)

CI가 이미지를 빌드한 뒤 git 매니페스트를 어떻게 업데이트하나(theory §6):

```bash
cat <<'EOF'
# 방안 비교
## A. CI가 config repo에 커밋 (흔함)
   CI 워크플로 끝에: 새 다이제스트로 매니페스트 수정 → config repo에 커밋/PR
   - CI가 config repo 쓰기 권한 (클러스터 권한은 여전히 불필요!)
   - 04의 다이제스트: image: repo@sha256:... 로 커밋

## B. ArgoCD Image Updater
   레지스트리를 감시 → 새 이미지 발견 시 git 자동 업데이트
   - CI가 git을 안 건드림 (레지스트리 push만)
   - write-back으로 git에 기록

## C. 사람이 PR (가장 통제됨)
   릴리스 담당이 다이제스트 업데이트 PR → 리뷰 → 머지
EOF
```

핵심: 어느 방안이든 **파이프라인은 여전히 클러스터 자격증명이 없습니다** — git 쓰기 권한만. 07에서 OIDC로 장기 키를 없앴는데, GitOps는 클러스터 접근 자체를 파이프라인에서 제거합니다.

## Step 5. app-of-apps — fleet 관리의 계층 (개념)

```yaml
# 최상위 Application이 다른 Application들을 관리
# root app → (git의 applications/*.yaml) → 각각이 Application
# 장점: 전체 fleet을 하나의 git으로, 계층적 관리
# 위험: root의 prune이 전체를 지울 수 있음 → root는 수동 sync 권장
```

eks 23의 fleet base/overlay가 GitOps에서 app-of-apps로 구조화됩니다 — 대규모 멀티클러스터의 표준 패턴.

## Step 6. 산출물 — GitOps 도입 체크리스트

```markdown
# GitOps(ArgoCD) 도입 설계
## 저장소 구조
- [ ] app repo(코드) ↔ config repo(매니페스트) 분리
- [ ] config repo: base/overlay(eks 23), 환경별 디렉터리
- [ ] 이미지 참조: 다이제스트(@sha256 — 04), 태그 아님

## sync 정책
- [ ] selfHeal: true (드리프트 교정) — 긴급 수정은 git으로만
- [ ] prune: true + 안전벨트(PR 리뷰, 중요 리소스 Prune=false)
- [ ] 프로덕션 최상위(app-of-apps root): 수동 sync 고려

## 경계
- [ ] 시크릿: External Secrets(eks 25) 또는 Sealed Secrets — git에 값 금지
- [ ] 이미지 업데이트: CI가 config repo 커밋 (or Image Updater)
- [ ] CI-CD 접점: git. 파이프라인은 클러스터 자격증명 없음

## 감사·롤백
- [ ] 롤백 = git revert (k8s 39)
- [ ] 배포 이력 = git log + ArgoCD history
- [ ] fleet: ApplicationSet (eks 23)
```

## Step 7. 고급 진도

```markdown
14 → ArgoCD: push→pull 패러다임, reconcile 루프           [ ]
→ 15(Flux): 다른 GitOps 구현, ArgoCD와 철학 비교
→ 17(Progressive Delivery): GitOps + 카나리(11) 자동화 = Argo Rollouts
```

## 정리

```bash
bash cleanup.sh
```
