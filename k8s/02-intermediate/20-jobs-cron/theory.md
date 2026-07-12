# 이론 — Job, 병렬 패턴, CronJob

> **🌱 17세 눈높이 비유: 전단지 아르바이트**
> - **Job** = "전단지 1000장 다 돌리면 끝나는 알바". 돌리다 넘어져도(실패) 다시 일어나 마저 돌립니다(재시도). 다 돌리면 퇴근(Completed) — 계속 서 있는 편의점 알바(Deployment)와 다릅니다.
> - **completions/parallelism** = "1000장을 5명이 나눠서" — 몇 명이 동시에(parallelism), 총 몇 묶음을(completions).
> - **CronJob** = "매주 토요일 아침마다 이 알바를 모집하는" 공고 시스템. 지난주 알바가 아직 안 끝났는데 이번 주 알바를 또 뽑을까요? — 그게 **동시성 정책**.

---

## 1. Job 기본

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: report }
spec:
  backoffLimit: 4               # 재시도 한도 (기본 6) — 초과 시 Job Failed
  activeDeadlineSeconds: 600    # 전체 제한시간 — 초과 시 강제 종료
  ttlSecondsAfterFinished: 3600 # 완료 1시간 후 자동 삭제 (청소!)
  template:
    spec:
      restartPolicy: Never      # Never 또는 OnFailure만!
      containers:
      - name: job
        image: myapp
        command: ["python", "report.py"]
```

### restartPolicy와 재시도의 두 경로

| restartPolicy | 실패 시 | 특징 |
|---------------|---------|------|
| OnFailure | **같은 Pod에서** 컨테이너 재시작 | Pod 수 적게 유지, 로그가 덮임(--previous로) |
| Never | **새 Pod** 생성 | 실패 Pod들이 남아 로그 부검 가능 (운영 선호) |

backoffLimit 카운트와 재시도 간격은 지수 백오프(10s, 20s, 40s...) — CrashLoopBackOff와 같은 원리.

> **💡 1.31+ Pod Failure Policy**: exit code별로 다르게 — "코드 42(데이터 오류)는 재시도 무의미하니 즉시 실패, 노드 축출은 카운트 제외" 같은 정밀 제어가 `podFailurePolicy`로 가능해졌습니다.

## 2. 병렬 패턴 3종

```yaml
# ① 단일 실행 (기본): completions=1, parallelism=1
# ② 고정 완료 수: "총 10번 성공해야 끝, 동시 3개"
spec: { completions: 10, parallelism: 3 }
# ③ 작업 큐: completions 미지정 + parallelism=5
#    → 워커들이 외부 큐를 비우고, "하나라도 성공 종료하면" Job 완료
```

### Indexed Job — 분할 정복의 표준

```yaml
spec:
  completions: 5
  parallelism: 5
  completionMode: Indexed     # 각 Pod에 0~4 인덱스 부여
```

각 Pod는 `JOB_COMPLETION_INDEX` 환경변수(와 hostname)로 자기 번호를 압니다 → "전체 데이터의 index/5번째 조각만 처리". 분산 빌드, 시뮬레이션 샤딩, ML 데이터 병렬의 기본기.

## 3. CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: { name: nightly }
spec:
  schedule: "30 2 * * *"            # 분 시 일 월 요일 (UTC 주의!)
  timeZone: "Asia/Seoul"            # 1.27+ GA — 이걸 쓰면 KST로
  concurrencyPolicy: Forbid         # Allow(기본)/Forbid(겹침 금지)/Replace(옛것 죽이고 새것)
  startingDeadlineSeconds: 300      # 놓친 스케줄을 5분까지만 보정 실행
  successfulJobsHistoryLimit: 3     # 완료 Job 보관 수 (기본 3)
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template: { ... }             # Job과 동일
```

### 동시성 정책 선택

| 정책 | 의미 | 적합 |
|------|------|------|
| Allow | 이전 실행이 안 끝나도 새로 시작 | 독립적 작업 |
| **Forbid** | 이전이 돌고 있으면 이번 스케줄 스킵 | 같은 데이터를 만지는 배치 (대부분) |
| Replace | 이전 것을 죽이고 새로 | "최신 1회만 의미 있는" 작업 |

### 놓친 스케줄의 진실

컨트롤러가 죽어 있던 동안의 스케줄은? — `startingDeadlineSeconds` 안이면 **보정 실행**됩니다(중복 실행 가능성의 출처 중 하나). 미설정 시: 놓친 횟수가 100회를 넘으면 에러로 멈춥니다. **멱등성이 필요한 또 하나의 이유.**

## 4. 운영 디테일

- 완료 Job의 Pod는 남습니다(로그 보존) — `ttlSecondsAfterFinished` 없으면 수천 개 쌓여 etcd/스케줄러 부담. **필수 설정으로 취급하세요**
- Job의 Pod 이름: `<job>-<random>`, CronJob의 Job 이름: `<cronjob>-<timestamp>` — 어느 스케줄의 산물인지 추적 가능
- 수동 즉시 실행: `kubectl create job manual-run --from=cronjob/nightly`  (운영에서 자주 씀!)

## 5. 소스코드에서 확인하기

- Job 컨트롤러: `pkg/controller/job/job_controller.go` — 성공/실패 카운팅과 백오프
- CronJob 스케줄 계산: `pkg/controller/cronjob/utils.go`의 `mostRecentScheduleTime` — "놓친 스케줄 100회" 로직이 여기 있습니다

## 요약 카드

| 질문 | 답 |
|------|----|
| Job의 성공 정의? | 컨테이너 exit 0 (지정 completions만큼) |
| 허용 restartPolicy? | Never / OnFailure (Always 불가) |
| 분할 정복 패턴? | Indexed Job + JOB_COMPLETION_INDEX |
| 겹침 방지 정책? | concurrencyPolicy: Forbid |
| 실행 보장 수준? | at-least-once → **멱등 설계 필수** |
| 완료 Job 청소? | ttlSecondsAfterFinished |
