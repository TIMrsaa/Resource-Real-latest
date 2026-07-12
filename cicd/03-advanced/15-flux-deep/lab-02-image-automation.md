# Lab 02 — 이미지 자동화: 14의 경계를 내장으로

14에서 "이미지 태그를 누가 git에 업데이트하나"가 GitOps의 경계였습니다. Flux의 image-controller가 이것을 자동화하는 것을 봅니다 — 04의 "다이제스트로 배포"가 완전 자동화되는 지점.

전제: lab-01의 Flux와 config repo(~/ci-lab/flux).

## Step 1. 이미지 자동화 컴포넌트 활성화

```bash
cd ~/ci-lab/flux
# image-reflector와 image-automation 컨트롤러 (기본 install에 없으면 추가)
flux install --components-extra=image-reflector-controller,image-automation-controller
kubectl -n flux-system get pods | grep image
```

## Step 2. 매니페스트에 자동 갱신 마커

image-controller가 어느 자리를 갱신할지 마커로 표시(theory §3):

```bash
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
        image: ghcr.io/stefanprodan/podinfo:6.7.1 # {"$imagepolicy": "flux-system:demo"}
        ports: [{ containerPort: 9898 }]
EOF
git add -A && git commit -qm "add image policy marker" && git push -q
```

`# {"$imagepolicy": ...}` 주석이 자동 갱신 대상 표시 — 이 자리가 policy가 고른 이미지로 자동 교체됩니다.

## Step 3. ImageRepository + ImagePolicy — 무엇을 감시하고 어떻게 고를지

```bash
# ① 레지스트리 스캔
flux create image repository demo \
  --image=ghcr.io/stefanprodan/podinfo \
  --interval=5m

# ② 태그 선택 정책 (semver — 최신 안정 버전)
flux create image policy demo \
  --image-ref=demo \
  --select-semver=">=6.0.0"

sleep 30
flux get image repository demo    # 발견된 태그 수
flux get image policy demo        # 선택된 최신 태그
```

예상: podinfo의 태그들을 스캔하고, semver 정책이 최신(예: 6.9.x)을 선택. ✅ **레지스트리를 감시**합니다 — CI가 새 이미지를 push하면 Flux가 압니다.

## Step 4. ImageUpdateAutomation — git 자동 커밋

```bash
flux create image update demo \
  --git-repo-ref=demo \
  --git-repo-path="./apps" \
  --checkout-branch=main \
  --push-branch=main \
  --author-name=fluxbot \
  --author-email=flux@example.com \
  --commit-template="[flux] update image to {{range .Updated.Images}}{{println .}}{{end}}"

sleep 60
# git에 자동 커밋이 생겼는지
git pull -q
git log --oneline -3
grep "image:" apps/demo/deployment.yaml
```

예상: `[flux] update image to ...` 자동 커밋이 생기고, 매니페스트의 이미지 태그가 **더 최신으로 자동 갱신**됨. ✅ **14의 경계 ②가 자동화됐습니다** — CI는 이미지를 push만 하고, Flux가 git 업데이트를 대신합니다.

배포까지 확인:

```bash
flux reconcile kustomization demo
sleep 15
kubectl -n flux-demo get deploy demo -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

## Step 5. 전체 흐름 — CI-CD 완전 자동화 (04·14·15 통합)

```markdown
# 완전 자동 GitOps 파이프라인 (이 랩이 완성한 것)
1. 개발자: app repo에 코드 push
2. CI(03~13): 테스트 → 이미지 빌드 → 레지스트리 push (다이제스트 — 04)
   ★ CI는 여기서 끝. git이나 클러스터를 안 건드림!
3. Flux image-controller: 레지스트리에서 새 이미지 발견 → config repo에 자동 커밋
4. Flux kustomize-controller: config repo 변경 감지 → 클러스터에 배포
5. drift 교정·prune 지속 (14)

→ CI와 CD가 완전 분리. 파이프라인은 클러스터 자격증명이 없음(14).
  단, 자동화의 대가: "실수한 이미지도 자동 배포" → policy·환경 분리로 통제
```

## Step 6. 자동화의 통제 — 아무거나 배포되면 안 됩니다

```markdown
# 이미지 자동화 통제 (안전벨트)
- ImagePolicy를 환경별로: staging은 최신, production은 명시적 semver(>=1.2.0 <2.0.0)
- production config repo는 자동 갱신 대신 PR (사람 리뷰 — 14의 prune 안전벨트와 같은 논리)
- 또는 staging에서 자동 검증 후 production으로 승격(PR)
- 04의 규율: 태그가 아니라 다이제스트를 고정 → 자동 갱신도 다이제스트로
```

핵심: 자동화가 강력할수록 **통제(policy·환경 분리·승격)** 가 중요합니다 — eks 17의 Karpenter 자동화에 limits/budgets가 필요했던 것과 같은 논리.

## Step 7. GitOps 도구 선택 (산출물 — 14+15 통합)

```markdown
# GitOps 도구 선택 (우리 조직)
## 원칙 (도구 무관 — OpenGitOps)
선언 / git 버전관리 / 자동 pull / 지속 reconcile

## ArgoCD vs Flux 판단
| 우리 상황 | 경향 |
|----------|------|
| 배포 상태를 UI로 보는 문화 | ArgoCD |
| 개발자 셀프서비스 대시보드 | ArgoCD |
| 이미지 자동화가 핵심 | Flux(내장) |
| 조합·확장·다른 툴 통합 | Flux |
| Progressive Delivery(17) | ArgoCD+Rollouts / Flux+Flagger |

## 우리 선택: ______ 근거: ______

## 공통 규율 (어느 도구든)
- app repo ↔ config repo 분리
- 시크릿: External Secrets/Sealed(값은 git 밖 — eks 25)
- 이미지: 다이제스트(04), 자동화는 환경별 policy로 통제
- 롤백: git revert. 프로덕션 자동 배포엔 승격 게이트
```

## Step 8. 고급 진도

```markdown
14~15 → GitOps 두 구현 (ArgoCD/Flux), push→pull 완성      [ ]
→ 16(Tekton): K8s 네이티브 CI (CD의 GitOps에 이어 CI도 K8s로)
→ 17(Progressive Delivery): GitOps + 카나리(11) 자동화
```

## 정리

```bash
bash cleanup.sh
```
