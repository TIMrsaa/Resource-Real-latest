# 자가 점검 퀴즈

**Q1.** GitOps 4원칙 중 "CI에서 kubectl apply"가 충족 못 하는 것과 그 의미는?

**Q2.** push 배포 대비 pull 배포의 보안상 장점은?

**Q3.** Synced/Healthy 2축에서 "OutOfSync + Healthy"와 "Synced + Degraded" 각각의 의미와 대응은?

**Q4.** selfHeal이 켜진 환경에서 긴급 패치의 올바른 절차는?

**Q5.** prune의 가치와 위험, 그리고 방어 장치 2가지는?

**Q6.** `kubectl rollout undo`가 GitOps에서 권장되지 않는 이유와 정식 롤백 절차는?

**Q7.** ArgoCD를 "모듈 30의 컨트롤러"에 빗대면 desired/current state는 각각 무엇인가요?

**Q8.** "Synced면 배포 성공"이 위험한 이유와 파이프라인의 올바른 종료 조건은?

---

## 정답

**A1.** ④ 지속적 조정. CI apply는 배포 **순간**에만 상태를 맞추고 떠납니다 — 이후의 드리프트(수동 변경, 부분 실패)를 아무도 감시하지 않습니다. GitOps는 상시 reconcile 루프가 계속 비교/수렴합니다.

**A2.** push는 외부(CI)가 클러스터 자격증명을 보유 — 유출 시 클러스터 장악. pull은 에이전트가 클러스터 **안**에서 Git을 읽기만 하므로, 외부에 풀리는 것은 Git 읽기 권한뿐. 권한의 방향이 안전한 쪽으로 뒤집힙니다.

**A3.** OutOfSync+Healthy: 잘 돌지만 Git과 다름 — 새 커밋 미반영이거나 드리프트 → diff 확인 후 동기화(또는 드리프트 원인 추적). Synced+Degraded: Git대로 만들었는데 그게 병듦(CrashLoop, replicas 미달) → 모듈 38 진단 루틴으로 (Git/ArgoCD 문제가 아니라 워크로드 문제).

**A4.** 클러스터를 직접 만지지 않습니다(selfHeal이 원복). ① 수정을 Git에 커밋/푸시 → 자동 동기화로 반영, 또는 ② 부득이하면 해당 앱 automated 일시 해제 → 수동 조치 → Git에 동일 변경 커밋 → automated 복원. 핵심: 끝났을 때 Git과 클러스터가 일치해야 합니다.

**A5.** 가치: 삭제도 Git이 진실이 됨 — 유령 리소스 제거. 위험: path/리포 설정 실수가 대량 삭제로 직결. 방어: 상태 리소스에 `Prune=false` 어노테이션, path 변경 PR에 diff 첨부 리뷰(+ 점진 도입, 백업).

**A6.** undo는 클러스터만 과거로 되돌려 Git(HEAD)과 어긋난 드리프트를 만듭니다 — automated면 곧 다시 HEAD로 끌려갑니다. 정식: `git revert <bad-commit>` + push — Git 자체를 되돌려 이력도 남고 에이전트가 알아서 수렴.

**A7.** desired state = **Git 리포의 렌더링 결과**(매니페스트), current state = 대상 클러스터의 실제 리소스. diff가 비교, sync가 수렴 — Reconcile(이름만 받고 전체 상태에서 수렴)과 동형입니다.

**A8.** Synced는 "apply 완료"일 뿐 — 새 버전이 죽어가는 중(Progressing→Degraded)일 수 있습니다. 파이프라인은 `argocd app wait --health`(또는 Health=Healthy 확인)로 끝나야 하고, Degraded는 상시 알림 대상이어야 합니다.
