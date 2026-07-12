# 흔한 함정 5선

## 1. selfHeal 켜둔 채 수동 hotfix

새벽 장애에서 `kubectl set image`로 급히 패치 → 몇 초 뒤 ArgoCD가 Git 값으로 원복 → "고쳤는데 왜 또 죽지?"의 무한 루프. 급할수록 **Git에 먼저** 커밋하거나, 최소한 해당 앱의 automated를 잠시 끄고 작업 후 Git 정합을 회복하세요. selfHeal 도입 시 팀 전체에 이 규칙을 공지하는 것까지가 도입입니다.

## 2. prune 첫날의 대량 삭제 사고

Application의 path/리포 설정 실수, 디렉터리 구조 변경 — prune이 "Git에 없네?"라며 운영 리소스를 쓸어버립니다. 방어: ① prune은 diff 리뷰가 자리잡은 후에 ② PVC 등엔 `Prune=false` ③ Application에 `preserveResourcesOnDeletion` 같은 보호 ④ path 변경류 PR은 `argocd app diff` 출력을 첨부해 리뷰.

## 3. Git은 깨끗한데 시크릿을 어떻게?

Secret을 평문으로 리포에 — GitOps 최악의 사고 유형. Git에 들어가는 순간 이력에 영원히 남습니다(지워도 reflog/포크에). 해법 계열: SealedSecrets(암호화해서 커밋), External Secrets Operator(리포엔 참조만, 실물은 AWS Secrets Manager — eks 파트), SOPS. **"시크릿 전략 없이 GitOps 전면 도입"은 미완성 설계입니다.** (cicd 파트에서 실습)

## 4. "Synced = 배포 성공"으로 착각

Synced는 "apply가 됐다"까지입니다 — 새 Pod가 CrashLoop여도 잠시 Synced/Progressing일 수 있고, 최종 Degraded를 아무도 안 보면 "배포했는데 죽어 있는" 채 방치됩니다. **Health까지 봐야 배포 완료**: Degraded 알림을 모니터링에 연결하고, 파이프라인은 `argocd app wait --health`로 끝나야 합니다.

## 5. 한 리포/한 브랜치에 전 환경

dev 커밋이 prod에 즉시 반영되는 구조(전 환경이 같은 path를 봄) — 환경 분리가 무너집니다. 정석: 환경별 디렉터리(overlays/dev, overlays/prod — 모듈 18) + 환경별 Application, 승격은 "dev 값을 prod 디렉터리로 옮기는 PR". 브랜치보다 **디렉터리 분리**가 GitOps에서 다루기 쉽습니다. (상세는 cicd 파트)

## 실무 사고 사례

> 플랫폼팀이 리포 대청소를 하며 디렉터리 구조를 바꿨습니다(apps/shop → services/shop). Application들의 path 수정 PR이 며칠 늦게 머지되는 사이, prune이 켜진 앱들이 "Git(옛 path)에 아무것도 없네?"라며 운영 리소스를 삭제하기 시작 — PVC 보호(Prune=false)를 해둔 앱만 데이터가 살았습니다. 복구는 Git 원복 + 자동 재동기화로 빨랐지만(GitOps의 역설적 장점), 교훈은 선명했습니다: ① 구조 변경과 path 수정은 **같은 PR**로 원자적으로 ② diff 출력 첨부를 리뷰 필수로 ③ 상태 리소스 보호는 미리. "Git이 진실"은 Git 실수도 충실히 집행한다는 뜻입니다.
