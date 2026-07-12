# 04 — 워크로드 컨트롤러: Deployment, ReplicaSet, DaemonSet

> "Pod를 직접 만들지 마라"고 했으니, 이제 Pod를 **대신 만들어주는 컨트롤러들**을 배웁니다. 실무 배포의 표준 단위.

## 학습 목표

1. Deployment → ReplicaSet → Pod 3단 구조와 각자의 책임을 설명합니다
2. 자가 치유(self-healing)를 직접 깨뜨려보며 검증합니다
3. 롤링 업데이트의 내부 동작(RS 2개의 비율 조절)과 maxSurge/maxUnavailable을 이해합니다
4. 롤백과 리비전 이력을 다룹니다
5. DaemonSet의 용도(노드마다 1개)를 압니다

## 선행 지식: 모듈 02(조정 루프), 03(Pod) · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-deployment-selfheal.md](./lab-01-deployment-selfheal.md) — 생성, 자가 치유 파괴 실험, 스케일
3. [lab-02-rolling-update.md](./lab-02-rolling-update.md) — 무중단 업데이트 관찰, 롤백
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요 시간: 이론 1h + 실습 1.5h
