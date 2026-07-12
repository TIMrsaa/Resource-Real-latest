# 자가 점검 퀴즈 (중급 졸업 시험 겸용)

**Q1.** Job에서 Pod의 `Completed` 상태가 의미하는 것과, Deployment였다면 일어났을 일은?

**Q2.** restartPolicy Never와 OnFailure의 재시도 방식 차이와 운영상 트레이드오프는?

**Q3.** "총 20개 작업을 동시 4개씩, 각 워커가 자기 몫을 인덱스로 아는" Job spec 핵심 필드 4개는?

**Q4.** K8s Job의 실행 보장 수준과, 그것이 강제하는 설계 원칙은?

**Q5.** 같은 테이블을 만지는 일일 배치의 concurrencyPolicy와 그 이유는?

**Q6.** CronJob이 KST 새벽 3시에 돌게 하는 두 가지 방법 중 권장은?

**Q7.** "배포 직후 배치를 즉시 한 번" 실행하는 명령은?

**Q8.** (종합) 매분 CronJob이 한 달 뒤 클러스터를 느리게 만들었습니다. 의심 지점 2가지는?

---

## 정답

**A1.** 컨테이너가 exit 0으로 **성공 종료**했다는 뜻 — Job의 목표 달성. Deployment(restartPolicy Always)였다면 종료를 장애로 보고 재시작해 CrashLoop이 됐을 것.

**A2.** Never: 실패마다 **새 Pod** — 실패 Pod들이 남아 시도별 로그 부검 가능, Pod 수 증가. OnFailure: **같은 Pod에서 컨테이너 재시작** — 깔끔하지만 이전 시도 로그가 덮임(`--previous`로 직전만).

**A3.** `completions: 20`, `parallelism: 4`, `completionMode: Indexed`, (Pod에서) `JOB_COMPLETION_INDEX` 환경변수.

**A4.** **at-least-once** (최소 1회 — 중복 가능). 따라서 배치는 **멱등**해야 합니다: upsert, 처리 마킹+스킵, 고유 키 제약.

**A5.** **Forbid** — 이전 실행이 안 끝났으면 이번 스케줄 스킵. 같은 데이터에 두 실행이 겹치면 정합성이 깨지기 때문. (단 수동 실행까지 막지는 못함 — 임계 작업은 앱 레벨 락 병행)

**A6.** ① `schedule`을 UTC로 환산(18 * * * *) ② `timeZone: "Asia/Seoul"` + `schedule: "0 3 * * *"` — **② 권장** (서머타임/가독성, 1.27+ GA).

**A7.** `kubectl create job <이름> --from=cronjob/<cronjob이름>`

**A8.** ① **완료 Job/Pod 누적** (ttlSecondsAfterFinished/historyLimit 미설정) → etcd 비대 ② 행(hang)된 active Job 누적 (activeDeadlineSeconds 미설정) — Forbid면 스케줄도 전부 막힘.
