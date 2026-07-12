# 37 — 대규모 튜닝: 1000+노드에서 무엇이 먼저 부러지나

> 클러스터는 어느 날 갑자기가 아니라 **예측 가능한 순서로** 병목에 닿습니다. etcd → API 서버 → 스케줄러 순으로 한계를 해부하고, 1000노드를 공짜로 시뮬레이션(kwok)하며 직접 관측합니다.

## 학습 목표

1. 공식 스케일 한계(노드 5,000 / Pod 150,000 등)와 그 근거를 압니다
2. etcd 병목(저장 한도, watch 증폭)과 API 서버 병목(expensive LIST, APF)을 구분합니다
3. API Priority and Fairness(APF)로 "누가 API 서버를 점유하는지" 관측·제어합니다
4. 스케줄러 처리량과 percentageOfNodesToScore의 트레이드오프를 압니다
5. kwok로 1000 가짜 노드를 만들어 대규모 스케줄링을 실측합니다

## 선행: 모듈 21(API 서버 내부), 22(etcd), 25(스케줄러 내부) · 환경: 공유 EKS + 로컬 kind(무료)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-apf-list-cost.md](./lab-01-apf-list-cost.md) — APF 관측, LIST 비용 실측 (EKS)
3. [lab-02-kwok-1000-nodes.md](./lab-02-kwok-1000-nodes.md) — 1000노드 시뮬레이션 + 스케줄러 처리량 (kind, 무료)
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
