# 이론 — GitOps 원칙과 ArgoCD 동작 모델

> **🌱 17세 눈높이 비유: 악보와 오케스트라**
> 기존 방식은 지휘자(배포자)가 단원(클러스터)에게 **말로** 지시하는 것 — 지시가 쌓이면 "지금 우리 뭘 연주 중이지?"를 아무도 모릅니다.
> GitOps는 **악보(Git)가 유일한 진실**입니다. 단원마다 악보를 보며 스스로 맞추고(pull), 누가 멋대로 다르게 연주하면(드리프트) 악보대로 되돌립니다(selfHeal). 연주를 바꾸려면? 악보를 고칩니다(커밋) — 절대 단원에게 귓속말하지 않습니다.

---

## 1. GitOps 4원칙 (OpenGitOps 표준)

1. **선언형**: 원하는 상태를 선언으로 기술 (모듈 10에서 완료)
2. **버전 관리 + 불변**: 그 선언의 유일 저장소는 Git — 모든 변경에 이력/서명/리뷰
3. **자동 pull**: 에이전트가 저장소에서 **끌어갑니다** (사람/CI가 클러스터에 밀어넣지 않음)
4. **지속적 조정**: 에이전트가 실제 상태를 감시하고 선언과 다르면 수렴시킵니다

→ ④가 핵심 차별점입니다. "CI에서 kubectl apply"는 ①②를 지켜도 **배포 순간에만** 맞춥니다 — 그 후의 드리프트는 아무도 모릅니다. GitOps는 **상시 감시 루프**입니다.

## 2. ArgoCD 구조 — 세 部品

```
┌─ ArgoCD (argocd ns) ─────────────────────────────┐
│ repo-server        Git clone + 렌더링(Helm/Kustomize/생YAML → 매니페스트)
│ application-controller   비교(diff) + 동기화(apply) — reconcile 루프 본체
│ api-server/UI      사람용 창구 (웹 UI, CLI)
└──────────────────────────────────────────────────┘
        ▲ 감시                  │ apply
       Git 리포                대상 클러스터(들)
```

### Application CRD — "무엇을 어디에"

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: shop, namespace: argocd }
spec:
  source:                              # 어디서 (Git)
    repoURL: https://github.com/me/k8s-config
    targetRevision: main               # 브랜치/태그/커밋
    path: apps/shop/overlays/prod      # Kustomize/Helm/생YAML 디렉터리
  destination:                         # 어디로
    server: https://kubernetes.default.svc    # 자기 클러스터
    namespace: shop
  syncPolicy:
    automated:
      prune: true                      # Git에서 지워진 리소스는 클러스터에서도 삭제
      selfHeal: true                   # 수동 변경(드리프트)을 자동 원복
    syncOptions: [CreateNamespace=true]
```

### 상태 2축 — Synced와 Healthy

| 축 | 질문 | 예 |
|----|------|----|
| Sync | Git과 클러스터가 같은가 | OutOfSync = diff 존재 |
| Health | 리소스가 건강한가 | Degraded = Deployment replicas 미달 등 |

"Synced인데 Degraded" = Git대로 만들었는데 그게 안 뜨는 것(CrashLoop 등 — 모듈 38로). "OutOfSync인데 Healthy" = 잘 돌지만 Git과 다름(드리프트 or 새 커밋 미반영).

## 3. 운영 패턴 3종

### prune — 지우는 것도 Git으로

파일을 리포에서 삭제 → ArgoCD가 클러스터의 해당 리소스도 삭제. 이게 없으면(수동 시절) "YAML은 지웠는데 클러스터에 유령 리소스 잔존"이 쌓입니다. 단, 양날: 리포 경로 실수가 대량 삭제가 될 수 있어 보호 장치(아래 pitfall)와 함께.

### sync wave — 순서가 필요할 때

`argocd.argoproj.io/sync-wave: "-1"` 어노테이션으로 적용 순서를 묶습니다 (wave -1 → 0 → 1...). CRD를 CR보다, DB를 앱보다 먼저 — 모듈 37의 "점진 투입"도 wave로 구현합니다.

### app-of-apps — 앱 목록도 GitOps로

Application들이 또 다른 Application(부모)의 Git 경로에 들어 있는 구조 — "클러스터에 뭘 배포할지의 목록" 자체가 Git에. 새 클러스터 부트스트랩이 "ArgoCD 설치 + 부모 앱 1개 등록"으로 끝납니다. (cicd 파트에서 실전)

## 4. 롤백의 재정의

```
긴급 상황에서도:  git revert <bad-commit> && git push    → ArgoCD가 알아서 이전 상태로
```

- 클러스터를 직접 만지지 않으므로 **롤백도 이력에 남고 리뷰 가능**
- `kubectl rollout undo`(모듈 04)와 차이: undo는 클러스터만 되돌려 **Git과 어긋난 상태**(드리프트)를 만듭니다 — GitOps에선 Git이 먼저입니다
- UI/CLI의 "History and Rollback"도 있지만 본질은 같습니다: 이전 리비전을 가리키게 하는 것

## 5. 안전장치들

| 장치 | 역할 |
|------|------|
| `selfHeal: false`로 시작 | 드리프트를 **알림만** 받고 수동 동기화 — 신뢰 쌓은 후 true |
| sync window | "금요일 밤엔 동기화 금지" 시간 창 |
| `Prune=false` (리소스 단위 어노테이션) | PVC 등 "절대 자동 삭제 금지" 마킹 |
| diff 미리보기 | PR에서 렌더링 결과 diff를 리뷰 (CI에서 `argocd app diff`) |

## 6. 소스/도구에서 확인하기

- OpenGitOps 원칙: https://opengitops.dev/
- ArgoCD 공식: https://argo-cd.readthedocs.io/
- Application 헬스 판정 로직: `argoproj/gitops-engine` (Deployment가 왜 Progressing인지 등)
- 대안 도구: Flux (같은 원리, 다른 모양 — cncf 파트에서 비교)

## 요약 카드

| 질문 | 답 |
|------|----|
| GitOps의 핵심 차별점? | 배포 순간이 아닌 **상시** 조정 루프 (4원칙의 ④) |
| push vs pull? | push=밖에서 밀어넣기(CI가 클러스터 권한 보유), pull=안의 에이전트가 끌어감 |
| Synced/Healthy의 차이? | Git과 같은가 / 그게 건강한가 — 독립 2축 |
| 드리프트 대응? | 감지(OutOfSync) → selfHeal이 자동 원복 |
| GitOps식 롤백? | git revert — 클러스터 직접 조작 금지 |
| ArgoCD의 정체? | "Git을 desired state로 삼는 컨트롤러" (모듈 30의 확대판) |
