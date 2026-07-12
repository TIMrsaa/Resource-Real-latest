# 흔한 함정 5선

## 1. 멱등성 없는 배치 + at-least-once의 만남

K8s는 "정확히 1회"를 보장하지 않습니다 — 노드 장애 재시도, 놓친 스케줄 보정, 사람의 수동 재실행. 포인트 적립이 두 번 되는 사고는 K8s 탓이 아니라 설계 탓입니다. **모든 배치 설계 리뷰의 첫 질문: "두 번 돌면?"**

## 2. schedule을 KST로 착각

`timeZone` 미지정 시 **UTC**입니다. "새벽 2시 배치"가 오전 11시(KST)에 돌아 피크 타임 DB를 두들기는 사고. `timeZone: "Asia/Seoul"`을 명시하세요 (1.27+ GA).

## 3. ttlSecondsAfterFinished 누락 → Job 수만 개

매분 도는 CronJob이 history limit으로 Job은 정리해도, 수동 생성 Job이나 다른 컨트롤러가 만든 Job은 영원히 쌓입니다. 완료 Pod 수천 개 = etcd 비대 + `kubectl get pods` 마비. **Job 템플릿에 ttl을 기본 탑재하세요.**

## 4. restartPolicy: Always를 Job에

Job은 Always를 거부합니다(생성 에러) — 하지만 진짜 함정은 OnFailure에서 "Pod가 안 남아 디버깅을 못 하는" 상황과, activeDeadlineSeconds 없이 **무한 행(hang)된 작업이 영원히 active**로 남아 Forbid 정책의 다음 스케줄을 전부 막는 것. 배치에는 deadline을 항상.

## 5. Forbid를 믿고 분산 락을 생략

Forbid는 "K8s가 보는 Job 겹침"만 막습니다 — 두 클러스터에서 같은 배치를 돌리거나, 수동 실행(`create job --from=`)과 스케줄이 겹치는 것은 못 막습니다. 진짜 임계 작업은 애플리케이션 레벨 락(DB advisory lock 등)이 최종 방어선.

## 실무 사고 사례

> 월말 정산 CronJob(Forbid, 멱등성 없음)이 평소 20분 → 데이터 증가로 70분이 걸리게 됐습니다. 한 시간짜리 스케줄과 겹치며 일부 스케줄이 스킵 → 담당자가 "누락분"을 수동 Job으로 재실행 → 그 사이 정상 스케줄도 돌기 시작 → **동시 2개 실행으로 이중 정산.** Forbid는 스케줄간 겹침만 막았고, 수동 실행은 막지 못했습니다. 교훈: ① 처리 시간 증가 추세를 모니터링(완료 시간 메트릭) ② 수동 재실행 runbook에 "active Job 확인" 단계 ③ 근본적으로 멱등 설계.
