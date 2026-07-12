# 이론 — reconcile 루프, sync 정책, ApplicationSet, 경계

> **🌱 17세 눈높이 비유: 자동 온도 조절기**
> - **push CD** = 사람이 창문을 직접 여닫아 온도 맞추기 — 나갈 때 열쇠(클러스터 자격증명)를 들고 다녀야 하고, 누가 언제 창문을 건드렸는지 모릅니다
> - **GitOps(pull)** = 온도조절기(ArgoCD)에 목표 온도(git)를 적어두면, 조절기가 **스스로** 현재 온도(클러스터)를 읽고 목표와 비교해 맞춥니다
> - **reconcile 루프** = "목표 22도 vs 현재 20도 → 히터 켜기"를 계속 반복
> - **selfHeal** = 누가 몰래 온도를 바꿔도(드리프트) 조절기가 목표로 되돌립니다
> - **prune** = 목표 목록에서 지운 항목(git에서 삭제한 리소스)을 조절기가 실제로도 끕니다
> - **경계** = 목표 온도표(git)에 비밀번호(시크릿)를 평문으로 적으면 안 됩니다

---

## 1. push vs pull — 화살표가 바꾸는 것

| | push CD (07·10) | pull CD (GitOps) |
|---|---|---|
| 배포 방향 | 파이프라인 → 클러스터 | 클러스터 → git (당김) |
| 클러스터 자격증명 | **파이프라인이 보유**(유출 위험) | 불필요(컨트롤러가 클러스터 내부) |
| 진실의 원천 | 파이프라인 로그(휘발) | **git**(영구·감사·롤백) |
| 드리프트 | 감지 못 함 | 컨트롤러가 감지·교정 |
| 멀티클러스터 | N개 자격증명 관리 | 각 클러스터가 자기 git을 당김(eks 23) |
| 롤백 | 재배포 파이프라인 | **git revert**(k8s 39) |

핵심 통찰: **클러스터 자격증명이 파이프라인에서 사라집니다.** 07에서 OIDC로 장기 키를 없앴는데, GitOps는 한 걸음 더 — 클러스터 접근 권한 자체가 파이프라인에서 불필요해집니다. 파이프라인이 탈취돼도 git 쓰기 권한뿐이고, 그마저 PR 리뷰로 게이트됩니다.

## 2. ArgoCD 구조 — reconcile 루프

```
Application (CRD): "이 git 경로를 이 클러스터/ns에 맞춰라"
   spec:
     source: { repoURL, path, targetRevision }    ← desired (git)
     destination: { server, namespace }
     syncPolicy: { automated: { selfHeal, prune } }

ArgoCD 컨트롤러의 reconcile 루프 (k8s 30 패턴):
   1. git에서 desired 매니페스트 가져오기 (+ kustomize/helm 렌더)
   2. 클러스터의 live 상태 조회
   3. diff 계산 → OutOfSync?
   4. (auto sync면) 차이를 apply
   5. health 평가 (리소스가 정상 동작하나)
```

두 개의 축을 구분하세요:

- **Sync status**: git과 클러스터가 같은가 (Synced / OutOfSync)
- **Health status**: 배포된 것이 정상인가 (Healthy / Progressing / Degraded)

이 둘은 독립입니다 — Synced인데 Degraded(git대로 배포됐지만 앱이 죽음), OutOfSync인데 Healthy(누가 손댔지만 동작함) 모두 가능. 진단의 첫 질문이 "어느 축의 문제인가"다.

## 3. sync 정책 — 자동화의 손잡이

```yaml
syncPolicy:
  automated:
    selfHeal: true      # 드리프트를 git으로 되돌림 (kubectl 수정 무효화)
    prune: true         # git에서 지운 리소스를 클러스터에서도 삭제
  syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
```

각 손잡이의 의미와 위험:

| 옵션 | 효과 | 위험 |
|------|------|------|
| `selfHeal: true` | kubectl 수정을 git 상태로 원복 | 긴급 수동 수정이 사라짐(그게 목적) |
| `prune: true` | git 삭제 = 클러스터 삭제 | git 실수가 프로덕션 삭제로 |
| `automated` 없음 | 수동 sync(사람이 버튼) | 01의 "배포 버튼" — Delivery |

**prune의 양날**: git이 진실이 되려면 prune이 필요합니다(git에서 지웠는데 클러스터에 남으면 진실이 둘). 하지만 git 실수(잘못된 삭제)가 프로덕션 삭제가 됩니다 — 그래서 PR 리뷰(02)가 GitOps의 안전벨트입니다.

## 4. sync wave와 hook — 순서와 훅

```yaml
# sync wave: 리소스 배포 순서 (11의 expand-contract 순서 제어)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"    # 낮을수록 먼저 (DB → 앱 순서)

# hook: sync 단계의 훅 (11의 CodeDeploy 훅 대응)
    argocd.argoproj.io/hook: PreSync      # PreSync/Sync/PostSync/SyncFail
```

- sync wave: CRD → Operator → 그것을 쓰는 리소스 순서, DB 마이그레이션(11 expand) → 앱
- hook: PreSync(마이그레이션 Job), PostSync(스모크 테스트), SyncFail(롤백 알림)

## 5. ApplicationSet — fleet 전개 (eks 23)

하나의 템플릿으로 여러 Application을 생성:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
spec:
  generators:
    - clusters: {}                        # 등록된 모든 클러스터
    - git:                                 # git의 디렉터리마다
        directories: [{ path: "apps/*" }]
    - matrix: [...]                        # 조합
  template:
    spec:
      source: { repoURL, path: "{{path}}" }
      destination: { server: "{{server}}" }
```

eks 23의 fleet 표준화가 여기서 실물이 됩니다: "클러스터 목록 × base/overlay"를 ApplicationSet이 자동 전개. 06의 동적 매트릭스가 CI였다면, ApplicationSet은 CD의 동적 전개입니다.

## 6. 경계 문제 — GitOps가 정직하게 다뤄야 할 것

### ① 시크릿 — git에 평문 금지

```
❌ Secret을 평문으로 git에 (base64는 인코딩, 25의 교훈)
✅ 방안:
   - Sealed Secrets: 공개키로 암호화해 git에, 클러스터가 복호화
   - External Secrets Operator: git엔 "참조"만, 실제 값은 Secrets Manager(eks 25)
   - SOPS + age/KMS: 파일 암호화
```

22(시크릿 관리)에서 깊이 다루지만, GitOps의 핵심 경계입니다: **모든 것을 git에** 두되 시크릿은 예외 처리.

### ② 이미지 태그 업데이트 — 누가 git을 바꾸나

```
CI가 이미지를 빌드했습니다 → git의 매니페스트를 새 다이제스트로 누가 업데이트?
   방안 A: CI 파이프라인이 git에 커밋 (CI가 git 쓰기 권한)
   방안 B: ArgoCD Image Updater (레지스트리를 감시해 git 자동 업데이트)
   방안 C: 사람이 PR (가장 통제되나 느림)
```

04의 "다이제스트로 배포"가 여기서 회수됩니다 — git의 매니페스트가 참조하는 것이 다이제스트여야 불변성이 지켜집니다.

### ③ CI와 CD의 책임 분계

```
CI(03~13)의 끝:  이미지 빌드 + 레지스트리 푸시 + git 매니페스트 업데이트
CD(ArgoCD)의 시작: git 변경 감지 → sync
접점: git (config repo — 앱 코드와 분리하는 것이 정석)
```

**app repo와 config repo 분리**: 앱 코드 저장소와 배포 매니페스트 저장소를 나눕니다 — CI가 config repo를 업데이트하고 CD가 그것을 봅니다. 섞으면 "매니페스트 커밋이 CI를 다시 트리거"하는 루프가 생깁니다.

## 7. 소스/도구에서 확인하기

- ArgoCD: https://github.com/argoproj/argo-cd (CNCF Graduated — 27 기여 대상)
- Application/ApplicationSet 문서: https://argo-cd.readthedocs.io
- OpenGitOps 원칙: https://opengitops.dev (선언·버전관리·자동조정·지속조정)
- Flux(15에서 비교): https://fluxcd.io

## 요약 카드

| 질문 | 답 |
|------|----|
| push vs pull의 핵심? | 클러스터 자격증명이 파이프라인에서 **사라집니다** |
| 진실의 원천? | git (감사·롤백·드리프트 교정) |
| reconcile 루프? | desired(git) vs live(클러스터) diff → 좁힘 (k8s 30 패턴) |
| 두 상태 축? | Sync(git과 같은가) / Health(정상 동작하나) — 독립 |
| selfHeal/prune? | 드리프트 원복 / git 삭제 반영 — prune은 양날(PR 리뷰가 안전벨트) |
| fleet 전개? | ApplicationSet (eks 23의 base/overlay × 클러스터) |
| 3대 경계? | 시크릿(평문 금지) / 이미지 태그 업데이트 / CI-CD 책임 분계 |
