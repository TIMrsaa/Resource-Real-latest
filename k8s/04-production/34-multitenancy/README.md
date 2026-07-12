# 34 — 멀티테넌시: 한 클러스터를 여럿이 쓰는 법

> "팀마다 클러스터"는 비싸고 "다 같이 한 클러스터"는 위험합니다. 그 사이의 스펙트럼 — ns 기반 소프트 멀티테넌시부터 vCluster까지 — 를 설계 기준과 함께 다룹니다.

## 학습 목표

1. 멀티테넌시 스펙트럼(ns 격리 → 노드 격리 → vCluster → 클러스터 분리)과 선택 기준을 압니다
2. "테넌트 ns 패키지"(RBAC+Quota+LimitRange+NetworkPolicy+PSA)를 하나의 셋으로 조립합니다
3. 노드 격리(taint+affinity 콤보)로 테넌트 전용 노드풀을 만듭니다
4. 지금까지 배운 격리 기술의 종합 시험장임을 확인합니다
5. vCluster의 구조(가상 control plane)를 개념적으로 이해합니다

## 선행: 모듈 09, 11, 12, 15, 32 (전부 부품으로 재등장) · 환경: 공유 EKS

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-tenant-package.md](./lab-01-tenant-package.md) — 테넌트 ns 패키지 조립
3. [lab-02-node-isolation.md](./lab-02-node-isolation.md) — 전용 노드풀 + 검증 매트릭스
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
