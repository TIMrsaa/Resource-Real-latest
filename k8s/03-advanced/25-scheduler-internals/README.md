# 25 — 스케줄러 내부: Scheduling Framework

> 모듈 12에서 "손잡이"를 배웠다면, 여기서는 그 손잡이가 꽂혀 있는 기계 — Scheduling Framework의 확장점 파이프라인 — 를 해부하고, 두 번째 스케줄러를 직접 띄워봅니다.

## 학습 목표

1. 스케줄링 사이클의 확장점(QueueSort→...→Bind)을 순서대로 압니다
2. 모듈 12의 기능들이 어느 플러그인인지 매핑합니다
3. 스케줄러 캐시/큐(activeQ, backoffQ, unschedulable)의 동작을 이해합니다
4. 멀티 스케줄러(schedulerName)를 배포해 동작을 검증합니다
5. 점수 가중치 조정으로 배치 성향(bin-packing vs spreading)을 바꾸는 원리를 압니다

## 선행: 모듈 02, 12, 21 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-observe-scheduling.md](./lab-01-observe-scheduling.md) — 이벤트/로그로 사이클 추적
3. [lab-02-second-scheduler.md](./lab-02-second-scheduler.md) — 두 번째 스케줄러 배포
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
