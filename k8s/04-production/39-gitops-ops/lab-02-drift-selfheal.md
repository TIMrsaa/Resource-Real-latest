# Lab 02 — 드리프트 치유, prune, 보호 장치

> lab-01의 guestbook에서 계속. (port-forward와 argocd 로그인 유지)

## Step 1. automated + selfHeal 켜기

```bash
argocd app set guestbook --sync-policy automated --self-heal
argocd app get guestbook | grep -A3 "Sync Policy"
```

## Step 2. 드리프트 자동 치유 — 운영자의 손버릇 교정 장치

터미널 1 (감시):
```bash
kubectl get deploy guestbook-ui -n guestbook -w
```

터미널 2 (몰래 수동 변경 — 모듈 10에서 "빚"이라 불렀던 그것):
```bash
kubectl scale deploy guestbook-ui -n guestbook --replicas=5
```

터미널 1 예상:
```
guestbook-ui   1/1 → 5/5 로 가다가...
guestbook-ui   1/1        ← 수 초 내 ArgoCD가 Git 값(1)으로 원복!
```

✅ **selfHeal의 실체**: 클러스터를 직접 만진 변경은 살아남지 못합니다. "그 hotfix 누가 지웠어?" — ArgoCD입니다. 이제 변경의 유일한 문은 Git이고, 이것이 통제이자 문화 장치입니다. (긴급 시 절차: selfHeal 일시 해제 or Git에 먼저 커밋)

## Step 3. prune — Git에서 지우면 클러스터에서도

남의 리포라 파일 삭제는 못 하므로, **개념 검증**을 거꾸로: 클러스터에 "Git에 없는 리소스"를 앱 라벨로 만들어 보면 —

```bash
kubectl create configmap orphan -n guestbook
argocd app get guestbook | grep -E "Sync Status"     # 여전히 Synced (orphan은 추적 대상 아님)
```

ArgoCD는 **자기가 만든(추적하는) 리소스만** 관리합니다 — orphan은 안 지웁니다(안전). 진짜 prune은 "추적 중인데 Git에서 사라진" 것에만 발동합니다:

```bash
# prune 동작 시뮬레이션: path를 리소스가 더 적은 디렉터리로 바꿔봅니다
argocd app set guestbook --sync-policy none          # 자동 동기화 잠시 정지
argocd app set guestbook --path kustomize-guestbook  # 같은 앱의 kustomize판 (리소스 구성이 다름)
argocd app diff guestbook 2>/dev/null | head -15     # 삭제될 것(-)과 생길 것(+)이 보입니다
argocd app sync guestbook --prune
kubectl get all -n guestbook                          # 옛 구성은 지워지고 새 구성으로
# 원복
argocd app set guestbook --path guestbook && argocd app sync guestbook --prune
argocd app set guestbook --sync-policy automated --self-heal
```

✅ prune은 "Git이 삭제의 진실"이 되게 합니다. 그래서 위험하기도 — 다음 Step의 보호 장치와 세트입니다.

## Step 4. 보호 장치 — 지워지면 안 되는 리소스

```bash
# PVC처럼 "자동 삭제 절대 금지" 리소스에 어노테이션 (개념 확인)
kubectl annotate configmap orphan -n guestbook argocd.argoproj.io/sync-options=Prune=false
kubectl get cm orphan -n guestbook -o jsonpath='{.metadata.annotations}'; echo
```

운영 체크리스트로 기억하세요:
- 상태 리소스(PVC/PV): `Prune=false` + 백업(모듈 36)
- 전 클러스터 파급 리소스(CRD): sync wave로 맨 앞 + prune 신중
- selfHeal 도입 순서: **알림만 → 업무시간 자동 → 전면 자동**

## Step 5. GitOps식 롤백 (개념 실행)

```bash
# UI: History and Rollback → 이전 리비전 선택. CLI:
argocd app history guestbook
argocd app rollback guestbook <ID>     # 이전 동기화 시점으로
```

✅ 단, 이것은 **응급 처치**입니다 — 클러스터는 과거인데 Git HEAD는 여전히 새 버전(어긋남). 정식 절차는 `git revert` + push로 **Git 자체를 되돌리는 것**(theory §4) — 그래야 이력과 진실이 함께 남습니다. (rollback 후 automated가 다시 HEAD로 끌고 가는 것도 주의 — 그래서 revert가 정답)

## Step 6. 산출물 — 우리 팀 GitOps 운영 수칙 초안

```markdown
# GitOps 운영 수칙 (초안)
1. 클러스터 변경의 유일한 문은 Git PR — kubectl 직접 변경 금지 (selfHeal이 지웁니다)
2. 긴급 패치: revert 가능한 커밋으로 Git에 먼저 → 자동 동기화 (직접 만지면 ①에 위배)
3. 롤백 = git revert (UI rollback은 응급 후 반드시 Git 정합 회복)
4. PVC/CRD엔 Prune=false 또는 wave 보호
5. selfHeal/prune은 점진 도입: diff 알림 → 부분 자동 → 전면 자동
6. Application의 health를 모니터링에 연결 (Degraded 알림 = 모듈 38 루틴 발동)
```

## 정리

```bash
bash cleanup.sh
```
