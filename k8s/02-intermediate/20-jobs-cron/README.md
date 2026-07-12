# 20 — Job과 CronJob: 끝이 있는 워크로드

> 중급 졸업 모듈. "계속 떠 있는" 워크로드만 다뤘던 지금까지와 달리, "끝나야 성공"인 배치의 세계: 재시도, 병렬 패턴, 스케줄, 중복 실행 제어.

## 학습 목표

1. Job의 완료/재시도 모델(completions/parallelism/backoffLimit)을 다룹니다
2. Indexed Job으로 작업 분할 패턴을 구현합니다
3. CronJob의 스케줄, 동시성 정책, 놓친 스케줄(startingDeadline) 처리를 압니다
4. "두 번 실행돼도 안전한가"(멱등성)가 배치 설계의 본질임을 이해합니다
5. ttlSecondsAfterFinished로 완료 Job 청소를 자동화합니다

## 선행: 모듈 03(restartPolicy), 04 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-jobs.md](./lab-01-jobs.md) — 재시도, 병렬, Indexed
3. [lab-02-cronjob.md](./lab-02-cronjob.md) — 스케줄, 동시성 정책, 실패 처리
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 45m + 실습 1.5h
**중급 수료**: 모듈 11~20 퀴즈 재점검 후 고급(03-advanced)으로.
