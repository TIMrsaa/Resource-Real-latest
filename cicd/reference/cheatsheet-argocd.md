# ArgoCD 치트시트

> 14의 두 구분이 전부입니다: **refresh(비교) vs sync(적용)**, **Git이 진실 vs 클러스터는 반영**. 모든 명령이 이 지도 위에 있습니다.

## 상태 읽기 (14)

```bash
argocd app list
argocd app get myapp                       # Sync/Health 상태 + 리소스 트리
argocd app diff myapp                      # 기대(Git) vs 실제 — 무엇이 다른가
argocd app history myapp                   # sync 이력 (롤백 대상 확인)
kubectl get app -n argocd                  # CRD로 직접 (컨트롤러 상태 = 진실)
kubectl get app myapp -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}'
```

## refresh vs sync — 개념이 명령이 됩니다 (14)

```bash
argocd app get myapp --refresh             # 비교만 다시 (Git 다시 읽기)
argocd app get myapp --hard-refresh        # 캐시 무시 비교 (repo-server 캐시 우회)
argocd app sync myapp                      # 적용
argocd app sync myapp --prune              # 삭제 동반 (Git에서 사라진 리소스 제거 — 양날!)
argocd app sync myapp --dry-run
argocd app rollback myapp <history-id>     # 이전 sync로 (단, Git이 진실 — 임시조치임을 기억)
```

## Application 핵심 필드 (14·17)

```yaml
spec:
  source:
    repoURL: https://github.com/org/gitops
    targetRevision: main                   # 태그/SHA 고정 가능 (04의 규율)
    path: apps/myapp
  destination: { server: ..., namespace: myapp }
  syncPolicy:
    automated:
      selfHeal: true                       # 드리프트 자동 복원 (수동 hotfix를 되돌림!)
      prune: true                          # Git에서 사라지면 삭제 (신중히)
    syncOptions: [CreateNamespace=true]
  ignoreDifferences:                       # 필드 소유권 다툼의 차선책 (25 카드 7)
    - group: apps
      kind: Deployment
      jsonPointers: [/spec/replicas]       # HPA가 주인인 필드 — 최선은 Git에서 제거
```

## sync 순서 제어 (14)

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"     # 낮을수록 먼저 (DB 마이그레이션 → 앱)
    argocd.argoproj.io/hook: PreSync       # 훅 (마이그레이션 Job — 11)
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

## 트러블슈팅 (25 카드 7)

```bash
# OutOfSync ↔ Synced 루프 → 어떤 필드가 튀나
argocd app diff myapp                      # 반복되는 diff 필드 = 소유권 다툼 용의자
kubectl -n argocd logs deploy/argocd-application-controller | grep myapp | tail
kubectl -n argocd logs deploy/argocd-repo-server | tail     # 렌더링(Helm/Kustomize) 실패는 여기
# Progressing에서 멈춤 → 커스텀 리소스의 health 판정 없음 (gitops-engine — 27)
# 웹훅 유실 의심 → poll 간격(기본 3m) 대기 여부 확인 (15)
```

## ApplicationSet (14 — 멀티클러스터·모노레포)

```yaml
spec:
  generators:
    - git:
        repoURL: https://github.com/org/gitops
        directories: [{ path: "apps/*" }]  # 디렉터리 = 앱 (20의 affected 배포와 결합)
  template:
    metadata: { name: "{{path.basename}}" }
    spec: { source: { path: "{{path}}" }, ... }
```

## Rollouts 병용 (17)

```bash
kubectl argo rollouts get rollout myapp --watch    # 카나리 단계 관찰
kubectl argo rollouts promote myapp                # 수동 승급
kubectl argo rollouts undo myapp                   # 롤백
# AnalysisTemplate 실패 → 자동 롤백 (관찰이 게이트 — 17)
```

## 운영 수칙 요약

```
- 매니페스트의 이미지는 다이제스트로 (04) — CI가 갱신 커밋 (push→pull 역전, 14)
- selfHeal 켜기 전: "수동 변경이 즉시 되돌려진다"를 팀 전체가 알아야 (14 pitfalls)
- prune은 앱별 명시 도입 — 전역 기본화는 사고의 지름길
- 시크릿은 Git에 평문 금지 — sealed/SOPS/ESO (22)
- admission 서명 검증과 결합하면 Git 무결성 + 아티팩트 무결성 (21)
```
