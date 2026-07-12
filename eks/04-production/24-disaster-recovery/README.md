# 24 — 재해 복구: "클러스터를 잃었다"에서 시작하는 설계

> k8s 36이 백업과 복구(ns 단위, RPO/RTO 언어)를 만들었다면, 이 모듈은 스케일을 올립니다 — **클러스터·리전을 통째로 잃는 시나리오**. 답은 더 큰 백업이 아니라 재건의 구조입니다: 4계층 재건 스택(인프라→플랫폼→워크로드→데이터), 격리 백업의 사다리(타리전→타계정→불변), 그리고 계층별 시간을 실측하는 재건 Game Day.

## 학습 목표

1. RTO를 **계층별로 분해**합니다 — 재건 스택 4층과 각 층의 지배 시간
2. 백업 격리의 사다리(같은 리전 → 크로스 리전 → 타계정 → 오브젝트 잠금)를 오릅니다
3. Velero 다중 BSL로 크로스 리전 백업을 실제 구성합니다
4. 재건 파이프라인(IaC + 애드온 표준 + GitOps + Velero)을 리허설하고 층별 시간을 잽니다
5. EKS식 pilot light(최소 CP 상시 + Karpenter 확장)의 비용 구조를 이해합니다

## 선행: k8s 36(필수 — 이 모듈의 1층), eks 21(재건=업그레이드의 형제), 23(failover·fleet), 17(pilot light의 엔진) · 환경: 공유 EKS
## ⚠️ 비용: 타리전 S3 소량 — cleanup에서 양 리전 버킷 정리

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-isolated-backup.md](./lab-01-isolated-backup.md) — 크로스 리전 BSL, 격리 사다리
3. [lab-02-rebuild-gameday.md](./lab-02-rebuild-gameday.md) — 4계층 재건 리허설 + RTO 분해표
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
