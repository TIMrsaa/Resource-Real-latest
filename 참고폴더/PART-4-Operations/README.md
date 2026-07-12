# Part 4 — Operations

## 학습 목표

운영 단계에서 마주칠 문제들을 시나리오로 직접 풀어보고, 비용을 지속 가능하게 관리하며, 클러스터를 안전하게 업그레이드하는 법.

## 모듈 구성

| 번호 | 모듈 | 핵심 |
|------|------|------|
| 16 | [troubleshooting](./16-troubleshooting/) | 7개 장애 시나리오 직접 재현 + 해결 |
| 17 | [cost-optimization](./17-cost-optimization/) | Cost Explorer, KubeCost, OpenCost 활용 |
| 18 | [upgrade-strategy](./18-upgrade-strategy/) | EKS / 노드 그룹 / addon 업그레이드 절차 |

## 선행 지식

- Part 1~3 완료
- 클러스터 (eks-study 또는 eks-study-tf) 떠 있음

## 비용 (Part 4 전체)

- 3개 모듈 × 평균 1.5시간 = 4.5시간
- 학습 대부분이 클러스터 위에서 수행 → EKS Control Plane + 노드
- 약 1 ~ 2 USD

## 커리큘럼 종료

이 Part 가 끝나면 EKS 학습 커리큘럼 전체 18개 모듈 완료입니다 🎉.

```bash
# 모든 학습이 끝났다면 클러스터 삭제로 비용 정지
eksctl delete cluster --name eks-study --region ap-northeast-2

# 또는 Terraform 으로 만들었다면
cd ../PART-3-Karpenter-KEDA/15-terraform-iac/terraform/
terraform destroy
```
