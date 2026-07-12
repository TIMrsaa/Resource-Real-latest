# 자가 점검 퀴즈

**Q1.** push CD와 pull CD(GitOps)의 차이를 "클러스터 자격증명" 관점에서 설명하세요. 07과 어떻게 이어지나요?

**Q2.** ArgoCD의 reconcile 루프를 단계로 서술하고, k8s의 어떤 패턴과 같은가요?

**Q3.** Sync status와 Health status는 왜 독립적인가요? 각각의 예를 들라.

**Q4.** selfHeal과 prune의 효과와 각각의 위험은? prune의 안전벨트는?

**Q5.** "git을 바꾸면 반영되고 kubectl로 바꾸면 원복된다" — 이것이 증명하는 GitOps 원칙은?

**Q6.** GitOps에서 롤백은 어떻게 하는가요? 그것이 감사에 주는 이점은?

**Q7.** GitOps의 세 가지 경계 문제와 각각의 해법은?

**Q8.** app repo와 config repo를 분리하는 이유 두 가지는?

---

## 정답

**A1.** push CD는 파이프라인이 클러스터에 `kubectl apply`를 밀므로 **클러스터 자격증명을 파이프라인이 보유**합니다(유출 위험). pull CD는 클러스터 안 컨트롤러가 git을 당겨오므로 파이프라인에 클러스터 자격증명이 **불필요**합니다(git 쓰기 권한만). 07에서 OIDC로 장기 키를 없앴다면, GitOps는 클러스터 접근 권한 자체를 파이프라인에서 제거합니다 — 한 걸음 더.

**A2.** ① git에서 desired 매니페스트 가져오기(+kustomize/helm 렌더) ② 클러스터의 live 상태 조회 ③ diff 계산(OutOfSync?) ④ (auto면) 차이 apply ⑤ health 평가. k8s 30의 **컨트롤러 reconcile 패턴**(desired vs live를 비교해 좁힘)과 같습니다 — Karpenter(eks 17), Velero(k8s 36)와 동일 구조.

**A3.** Sync는 "git과 클러스터가 같은가", Health는 "배포된 것이 정상 동작하나"로 서로 다른 질문입니다. 예: Synced+Degraded(git대로 배포됐지만 이미지가 잘못돼 앱이 죽음), OutOfSync+Healthy(누가 kubectl로 손댔지만 동작함). 진단 시 어느 축의 문제인지 먼저 구분해야 처방이 갈립니다.

**A4.** selfHeal: 드리프트(kubectl 수정)를 git 상태로 원복 — 위험은 긴급 수동 수정이 사라짐(그게 목적). prune: git에서 지운 리소스를 클러스터에서도 삭제("git이 진실"의 완성) — 위험은 git 실수가 프로덕션 삭제. prune 안전벨트: PR 리뷰(02), 중요 리소스에 Prune=false, 최상위 app-of-apps는 수동 sync.

**A5.** **git이 유일한 진실의 원천**이라는 원칙. kubectl 변경은 드리프트로 간주되어 selfHeal이 원복하고, git 변경만이 클러스터에 반영됩니다 — 따라서 "무엇이 배포됐나"는 git의 현재 상태이고, 모든 변경 이력이 git log에 남아 감사됩니다.

**A6.** `git revert`(잘못된 커밋을 되돌리는 커밋을 push) → ArgoCD가 그것을 감지해 이전 상태로 sync. 이점: 롤백조차 git에 기록되어 "누가 언제 무엇을 왜 되돌렸는지"가 감사되고, 롤백이 재배포 파이프라인이 아니라 git 조작 하나로 끝납니다(01의 "30분 내 롤백").

**A7.** ① 시크릿: git에 값을 두면 안 됨(base64는 암호화 아님) → External Secrets(값은 Secrets Manager, git엔 참조)/Sealed Secrets(암호문). ② 이미지 태그 업데이트: CI가 config repo 커밋 / ArgoCD Image Updater / 사람 PR — 어느 쪽이든 다이제스트(04)로. ③ CI-CD 책임 분계: 접점은 git, app repo와 config repo 분리.

**A8.** ① 무한 루프 방지: 앱 코드와 매니페스트가 같은 repo면 CI가 매니페스트를 업데이트하는 커밋이 CI를 다시 트리거합니다. ② 감사 명확성: "코드 변경"과 "배포 변경"의 히스토리가 분리되어 무엇이 왜 배포됐는지 추적이 명확합니다. (+ 권한 분리: CI는 config repo 쓰기만, 앱 개발자는 app repo)
