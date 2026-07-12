# 15. Terraform IaC — 전체 인프라 코드화

## 학습 목표

지금까지 eksctl + Helm + kubectl 로 점진 구축한 클러스터를 **Terraform 단일 코드** 로 재현.

- VPC + EKS Cluster + Managed Node Group → `terraform-aws-modules/eks`
- Karpenter, KEDA, AWS LB Controller, EBS CSI → Helm provider
- IRSA → IAM module
- Outputs / state 관리

## 선행 지식

- 모듈 10~14 완료
- Terraform 1.7+ 설치됨
- (이미 떠있는 `eks-study` 클러스터 — 본 lab 은 별도 이름으로 만들어 비교)

## 진행 순서

1. [theory.md](./theory.md) — IaC 가치 + 모듈 구조 (15분)
2. [lab-01-cluster.md](./lab-01-cluster.md) — VPC + EKS 클러스터 (40분)
3. [lab-02-addons.md](./lab-02-addons.md) — Karpenter, KEDA, LB Controller (40분)
4. [lab-03-destroy.md](./lab-03-destroy.md) — terraform destroy 로 깨끗이 정리 (10분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 비용

새 클러스터를 만드므로 추가 비용. 학습 시간 + cleanup 까지 약 1.5 USD.

## 다음 단계

→ **Part 4** — 운영/트러블슈팅
