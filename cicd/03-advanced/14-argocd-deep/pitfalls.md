# 흔한 함정 5선

## 1. 시크릿을 git에 base64로

"모든 것을 git에"라는 GitOps 원칙을 순진하게 적용해 Secret을 base64로 커밋하는 것 — base64는 암호화가 아니라 인코딩입니다(eks 25). git 히스토리에 영구히 남고, config repo가 퍼블릭이거나 접근 권한이 넓으면 그대로 유출됩니다. "모든 것을 git에"의 정확한 의미는 "값이 아니라 참조를 git에"다: External Secrets Operator(git엔 참조, 값은 Secrets Manager) 또는 Sealed Secrets(암호문을 git에). 시크릿은 GitOps의 명시적 예외입니다.

## 2. prune을 켜고 PR 리뷰 없이 config repo 운영

prune은 "git이 진실"의 필수 조건이지만(git에서 지우면 클러스터에서도 삭제), 동시에 git 실수가 프로덕션 삭제가 되는 문입니다. config repo에 브랜치 보호(02) 없이 prune을 켜면 — 잘못된 머지, 실수한 `git rm` 하나가 서비스를 지웁니다. GitOps에서 PR 리뷰는 스타일이 아니라 **prune의 안전벨트**입니다. 그리고 중요 리소스(PVC, 네임스페이스)에는 `Prune=false`를, 최상위 app-of-apps root는 수동 sync를.

## 3. app repo와 config repo를 안 나누기

앱 코드와 배포 매니페스트를 같은 저장소에 두면 — CI가 이미지를 빌드하고 매니페스트를 업데이트하는 커밋이 **CI를 다시 트리거**하는 무한 루프가 생기거나, path 필터로 그것을 막느라 복잡해집니다. 그리고 "코드 변경"과 "배포 변경"의 히스토리가 섞여 감사가 흐려집니다. 정석은 분리: app repo(CI가 이미지 빌드) → config repo(CI가 다이제스트 업데이트) → ArgoCD가 config repo를 봅니다.

## 4. Sync와 Health를 혼동해 오진

ArgoCD의 두 상태 축은 독립입니다(theory §2). "Synced인데 앱이 안 됨"(git대로 배포됐지만 이미지가 잘못됨 → Degraded), "OutOfSync인데 잘 됨"(누가 손댔지만 동작 → selfHeal 대기) 모두 가능합니다. 장애 시 "Sync 문제인가 Health 문제인가"를 먼저 구분하지 않으면 엉뚱한 곳을 팝니다 — git을 고쳐야 하나(Sync), 이미지·설정을 고쳐야 하나(Health)는 다른 처방입니다.

## 5. selfHeal을 켜고 긴급 수동 수정을 기대

장애 대응 중 `kubectl edit`으로 급히 고쳤는데 1분 뒤 원복되어 당황하는 것 — selfHeal이 git으로 되돌린 것입니다(그게 목적). GitOps에서 **모든 변경은 git을 거쳐야** 합니다. 긴급 상황을 위한 답은 selfHeal을 끄는 게 아니라 **빠른 git 경로**입니다: hotfix 브랜치의 빠른 PR, 또는 임시로 그 Application의 auto-sync를 끄고 수동 수정 후 git 반영. "selfHeal 때문에 긴급 대응이 안 된다"면 git 워크플로가 느린 것이지 GitOps가 틀린 게 아닙니다.

## 실무 사고 사례

> GitOps로 전환한 팀이 프로덕션 장애를 맞았습니다 — 결제 서비스가 응답을 멈췄습니다. 온콜이 원인을 찾아 `kubectl edit`으로 환경변수를 급히 고쳤고 서비스가 살아났습니다. 안도하며 근본 원인을 조사하던 중, 3분 뒤 서비스가 다시 죽었습니다 — ArgoCD의 selfHeal이 git 상태(잘못된 환경변수)로 원복한 것입니다. 온콜은 다시 고쳤고, 또 원복됐습니다. 이 "고치고 원복되는" 사이클이 20분간 반복되며 장애가 길어졌습니다. 결국 누군가 ArgoCD를 이해하고 그 Application의 auto-sync를 끈 뒤 수동 수정, 그리고 git에 반영해서야 안정됐습니다. 사후 분석의 교훈 둘: ① 팀이 GitOps의 selfHeal을 이해하지 못한 채 도입했습니다(kubectl이 통하지 않는 세계인데) ② 긴급 수정의 정규 경로(hotfix PR, 또는 auto-sync 일시 중지 절차)가 runbook에 없었습니다. 조치: GitOps 장애 대응 runbook 작성("selfHeal 환경에서 긴급 수정은 git으로, 불가피하면 auto-sync 중지 후"), 팀 교육, 그리고 config repo의 hotfix PR을 5분 내 머지 가능하게 리뷰 SLA 조정. 교훈: **GitOps는 도구가 아니라 규율입니다** — kubectl이 진실이던 세계에서 git이 진실인 세계로 옮기면, 장애 대응의 근육 기억부터 바꿔야 합니다.
