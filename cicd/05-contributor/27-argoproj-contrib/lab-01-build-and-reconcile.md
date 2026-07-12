# Lab 01 — 빌드, 로컬 실행, 그리고 14의 reconcile을 코드로 추적

argo-cd를 소스에서 빌드해 kind를 상대로 돌리고, 사용자로 배운 refresh→diff→sync를 개발자의 눈으로 봅니다.

전제: Go 1.23+, kind, kubectl, docker. 메모리 8GB 권장.

## Step 1. 클론과 코드 지도 확인

```bash
mkdir -p ~/contrib && cd ~/contrib
git clone --depth 50 https://github.com/argoproj/argo-cd.git && cd argo-cd

# theory §2의 지도를 눈으로
ls cmd/                                        # 컴포넌트별 main
grep -n "func.*processAppRefreshQueueItem" controller/appcontroller.go | head -2   # reconcile 진입
grep -n "CompareAppState" controller/state.go | head -2                            # diff 계산
grep -rn "gitops-engine" go.mod | head -3                                          # ★ 2저장소 경계
```

✅ go.mod의 `github.com/argoproj/gitops-engine` — sync·diff의 심장이 국경 너머에 있음을 확인(theory §3).

## Step 2. 경계 넘어가기 — gitops-engine 쪽 훑기

```bash
git clone --depth 20 https://github.com/argoproj/gitops-engine.git ../gitops-engine
ls ../gitops-engine/pkg/                       # sync, diff, health, utils ...
grep -n "func GetHealthStatus" ../gitops-engine/pkg/health/*.go | head -3
grep -rn "syncwaves" ../gitops-engine/pkg/sync/ | head -3
```

✅ 14의 sync wave·health 판정이 **엔진 저장소**의 코드입니다 — "wave 순서가 이상해요"는 이쪽 소관일 수 있습니다(경계 판정 연습).

## Step 3. 로컬 실행 — 컨트롤러는 그냥 Go 프로세스

```bash
kind create cluster --name argo-dev -q
kubectl create namespace argocd

cd ~/contrib/argo-cd
# 공식 개발 문서의 로컬 실행 (goreman으로 컴포넌트들을 로컬 프로세스로)
# 요구 도구가 없으면: make dev-tools-image 또는 개발 가이드의 대체 경로 참조
make start-local ARGOCD_GPG_ENABLED=false 2>&1 | tail -5 &
sleep 90
kubectl config set-context --current --namespace=argocd
ps aux | grep -cE "argocd-(server|repo-server)|application-controller" || true
```

예상: 컴포넌트들이 **로컬 프로세스**로 떠서 kind에 붙습니다(Pod가 아닙니다!). ✅ k8s 42의 명제 재확인 — 컨트롤러는 kubeconfig를 가진 평범한 프로세스이고, 그래서 IDE 중단점·printf 디버깅이 가능합니다. (start-local이 환경 문제로 어려우면: 공식 매니페스트로 설치하고 application-controller만 스케일 0 후 로컬 실행하는 절충도 개발 가이드에 있습니다.)

## Step 4. Application 하나로 reconcile 관찰 — 14의 복습을 로그로

```bash
# 14에서 쓰던 예제 앱
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: guestbook, namespace: argocd }
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination: { server: https://kubernetes.default.svc, namespace: default }
EOF

sleep 20
# 컨트롤러 로그에서 reconcile의 발자국 (로컬 프로세스 로그)
grep -E "Refreshing app|Comparing app|guestbook" /tmp/argocd-*.log 2>/dev/null | tail -5 || \
  kubectl get app guestbook -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}'; echo
```

예상: OutOfSync(아직 sync 안 함 — refresh는 **비교만**, 14의 구분). sync를 걸고 다시:

```bash
kubectl patch app guestbook --type=merge -p '{"operation":{"sync":{}}}'
sleep 30
kubectl get app guestbook -o jsonpath='{.status.sync.status}{" / "}{.status.health.status}'; echo
```

예상: `Synced / Healthy`. ✅ refresh(비교)→OutOfSync 판정→sync 오퍼레이션→Healthy — 14의 수명주기가 내 로컬 컨트롤러의 처리로 재현됐습니다.

## Step 5. 코드 수정 → 동작 변화 확인 — 개발자의 증명

```bash
# 비교 로직 진입점에 식별 로그 한 줄 (실험 — 커밋 금지)
grep -n "func (m \*appStateManager) CompareAppState" controller/state.go | head -1
# 위 함수 초입에 log.Infof("[mine] comparing %s", app.Name) 추가 후:

# 컨트롤러만 재시작 (start-local 은 프로세스 재기동으로 반영)
# 재기동 후 refresh 트리거:
kubectl annotate app guestbook argocd.argoproj.io/refresh=normal --overwrite
sleep 15
grep "\[mine\]" /tmp/argocd-*.log 2>/dev/null | tail -2 && echo "→ 내 코드가 reconcile 경로에서 돌았다 ✅"
git checkout -- controller/state.go
```

✅ **수정→재시작→트리거→로그**의 루프 — eks 28·cicd 26과 같은 물리적 기초가 argo-cd에서도 완성.

## Step 6. UI라는 문 확인 (TS 개발자용)

```bash
ls ui/src/app/                                # applications, settings ... React 컴포넌트
grep -rn "OutOfSync" ui/src/app/applications/ --include="*.tsx" -l | head -3
echo "→ UI 이슈는 'component:ui' 라벨 — Go 없이 기여 가능한 문 (theory §6)"
```

## Step 7. 산출물 — 경계 판정 카드

```markdown
# argo-cd 기여 지도 (오늘 확인한 것)
| 증상/변경 | 저장소·패키지 | 확인 파일 |
|-----------|--------------|----------|
| refresh·sync 결정 로직 | argo-cd controller/ | appcontroller.go |
| diff 계산·정규화 | gitops-engine pkg/diff (+argo-cd normalizer) | state.go에서 호출 추적 |
| sync wave·hook 실행 | gitops-engine pkg/sync | syncwaves 검색 |
| health 판정 | gitops-engine pkg/health | GetHealthStatus |
| Helm/Kustomize 렌더 | argo-cd reposerver/ | repository.go |
| 화면·표시 | argo-cd ui/ (React·TS) | applications/*.tsx |
```

## 정리

lab-02에서 테스트와 기여 경로로 이어집니다. 클러스터·클론 유지.
