# Lab 02 — CronJob: 스케줄, 겹침 제어, 운영 루틴

## Step 1. 1분마다 도는 CronJob

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata: { name: ticker }
spec:
  schedule: "* * * * *"
  timeZone: "Asia/Seoul"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 2
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 600
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: tick
            image: public.ecr.aws/docker/library/busybox:stable
            command: ["sh", "-c", "date; echo tick"]
EOF
kubectl get cronjob ticker
sleep 70; kubectl get jobs | grep ticker
```

예상: `ticker-<timestamp>` Job이 생기고 Complete. LAST SCHEDULE이 갱신됩니다.

## Step 2. Forbid 검증 — 겹침이 스킵되는가

```bash
# 90초 걸리는 작업으로 변경 (1분 주기보다 깁니다!)
kubectl patch cronjob ticker --type=json -p='[{"op":"replace","path":"/spec/jobTemplate/spec/template/spec/containers/0/command","value":["sh","-c","date; echo long work; sleep 90"]}]'
sleep 130
kubectl get jobs | grep ticker | tail -3
kubectl get events --sort-by=.lastTimestamp | grep -i "JobAlreadyActive\|skip" | tail -2
```

예상: 매분이 아니라 **격분**으로만 Job이 생깁니다 — 이전 실행이 안 끝나서 스케줄이 스킵됨(이벤트에 기록). 같은 데이터를 만지는 배치의 안전장치.

> Replace로 바꿔 같은 실험을 하면: 90초짜리가 60초 만에 **죽고** 새것이 시작 — "끝까지 가는 게 의미 없는" 작업용임을 체감할 수 있습니다.

## Step 3. 운영 루틴 ① — 수동 즉시 실행

"배포 후 배치를 한 번 돌려보자" — cron을 기다리지 않습니다:

```bash
kubectl create job ticker-manual --from=cronjob/ticker
kubectl logs job/ticker-manual -f
```

✅ jobTemplate을 그대로 복사한 1회성 Job. 운영에서 가장 자주 쓰는 CronJob 명령입니다.

## Step 4. 운영 루틴 ② — 일시 중지

"DB 점검 중이니 배치 멈춰" :

```bash
kubectl patch cronjob ticker -p '{"spec":{"suspend":true}}'
kubectl get cronjob ticker     # SUSPEND: True
# 점검 후
kubectl patch cronjob ticker -p '{"spec":{"suspend":false}}'
```

> 💡 suspend 동안 놓친 스케줄은 (startingDeadlineSeconds에 따라) 재개 시 보정 실행될 수 있습니다 — "멈췄다 켜면 밀린 게 한꺼번에?"를 막으려면 deadline을 짧게 설정.

## Step 5. 실패 알림의 기초 — 실패 Job 찾기

```bash
# 일부러 실패하는 CronJob 하나
kubectl create cronjob failer --image=public.ecr.aws/docker/library/busybox:stable \
  --schedule="* * * * *" -- sh -c 'exit 1'
sleep 70
kubectl get jobs --field-selector status.successful!=1 | grep failer
```

운영에서는 이 패턴을 모니터링이 대신합니다: `kube_job_status_failed` 메트릭(kube-state-metrics)에 알람 — 관측 스택(eks 파트 12)과 연결되는 지점.

## Step 6. 멱등성 사고 훈련 (설계 과제)

다음 배치를 멱등하게 설계하세요 (정답은 없고, 원칙 적용을 점검):
1. "어제 주문을 집계해 일별 매출 테이블에 INSERT" → (힌트: INSERT → **UPSERT**(날짜 PK), 또는 "이미 있으면 스킵")
2. "미발송 이메일 발송" → (힌트: 발송 전 상태를 'sending'으로 마킹+고유 키, 발송 후 'sent' — 두 번 돌아도 sent는 건너뜀)
3. "30일 지난 파일 삭제" → (이건 자연 멱등 — 두 번 지워도 같은 결과. 이런 작업을 늘리는 게 좋은 설계)

## 정리

```bash
bash cleanup.sh
```
