# 14 — Probe와 Lifecycle: 무중단의 실체

> 여러 모듈에서 복선으로 깔린 것들의 회수: readiness가 EndpointSlice를 움직이고(05), 롤링 업데이트를 무중단으로 만들고(04), SIGTERM 처리(03)가 배포 중 504를 없앱니다.

## 학습 목표

1. liveness / readiness / startup probe의 용도와 실패 시 결과를 정확히 구분합니다
2. 잘못된 liveness가 만드는 "재시작 폭풍"을 재현하고 이해합니다
3. graceful shutdown(SIGTERM→drain→종료)을 구현하고 무중단 배포를 부하 중에 검증합니다
4. preStop hook이 필요한 경우(레이스 컨디션)를 압니다

## 선행: 모듈 03, 04, 05 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-probes.md](./lab-01-probes.md) — 3종 probe 동작/오동작 실험
3. [lab-02-graceful-shutdown.md](./lab-02-graceful-shutdown.md) — 부하 중 배포로 무중단 검증
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
