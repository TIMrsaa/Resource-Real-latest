# 10. Karpenter 설치 + NodePool

## 학습 목표

- Karpenter 가 Cluster Autoscaler (CA) 와 어떻게 다른지 이해
- IRSA + IAM 셋업 → Helm 설치
- `NodePool` (어떤 Pod 을 받을지) + `EC2NodeClass` (어떤 EC2 를 만들지) 정의
- Pending Pod 발생 → Karpenter 가 노드 자동 추가하는 것 시연
- Pod 삭제 → 노드 자동 회수 (consolidation)

## 선행 지식

- Part 1, 2 완료
- `eks-study` 클러스터 떠 있음, OIDC 활성화

## 진행 순서

1. [theory.md](./theory.md) — Karpenter 동작 (20분)
2. [lab-01-install.md](./lab-01-install.md) — IAM + Helm 설치 (35분)
3. [lab-02-first-nodepool.md](./lab-02-first-nodepool.md) — NodePool + 자동 노드 추가 (25분)
4. [lab-03-consolidation.md](./lab-03-consolidation.md) — 노드 회수 시연 (15분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 비용

본 lab 동안 Karpenter 가 노드 1~3대 (Spot) 를 늘렸다 줄였다 합니다. 1.5시간 가정 약 0.1 USD.

## 다음 모듈

→ [11-karpenter-advanced](../11-karpenter-advanced/)
