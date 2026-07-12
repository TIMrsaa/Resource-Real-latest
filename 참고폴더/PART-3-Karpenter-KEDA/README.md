# Part 3 — Karpenter + KEDA (운영 심화)

## 학습 목표

EKS 운영의 두 핵심 자동화:

- **Karpenter**: 노드(인프라) 자동 스케일링 — 빠른 provisioning + 비용 최적화 (Spot, Consolidation)
- **KEDA**: 워크로드(Pod) 자동 스케일링 — 이벤트 기반 (큐, 메트릭, 시간)

이 둘의 조합이 EKS 의 "탄력적 운영" 의 정수.

## 모듈 구성

| 번호 | 모듈 | 핵심 |
|------|------|------|
| 10 | [karpenter-install](./10-karpenter-install/) | Karpenter Helm 설치, NodePool/EC2NodeClass CRD |
| 11 | [karpenter-advanced](./11-karpenter-advanced/) | Spot, Disruption, Consolidation, 비용 비교 |
| 12 | [keda-basics](./12-keda-basics/) | KEDA 설치, ScaledObject, scale-to-zero |
| 13 | [keda-event-driven](./13-keda-event-driven/) | SQS / Kafka / Prometheus 트리거 |
| 14 | [karpenter-keda-combo](./14-karpenter-keda-combo/) | **시나리오 절정**: 큐 폭주 → Pod 폭증 → 노드 자동 증설 |
| 15 | [terraform-iac](./15-terraform-iac/) | 전체 인프라를 Terraform 모듈로 |

## 선행 지식

- Part 1, 2 완료
- `eks-study` EKS 클러스터 (Module 05 의 ClusterConfig 기반) 떠 있음
- AWS LB Controller, EBS CSI 동작 중
- IRSA 메커니즘 이해

## 사용할 클러스터

Part 2 와 같은 클러스터 (`eks-study`). 만약 Part 2 종료 시 삭제했다면 다시 생성:

```bash
eksctl create cluster -f ../PART-2-EKS-Practice/05-eks-cluster-eksctl/manifests/cluster.yaml
```

## Part 3 의 새 학습 부담 요약

기존 Part 1~2 와 다르게 추가로 알아야 할 것:
- Karpenter CRD: NodePool, EC2NodeClass, NodeClaim
- KEDA CRD: ScaledObject, ScaledJob, TriggerAuthentication
- Spot Instance Termination Handling
- 외부 큐(SQS, Kafka) 메트릭을 K8s 가 어떻게 읽는가

## 예상 비용 (Part 3 전체)

- 6개 모듈 × 평균 2.5시간 = 15시간 학습 가정
- EKS Control Plane: 15 × $0.10 = $1.50
- Spot 노드 (변동, 평균 3대 가정): 15 × 3 × $0.016 = $0.72
- Module 14 부하 테스트 (대량 노드 폭증): 약 $1
- Kafka in-cluster (3 node, 4시간): 약 $0.5
- ALB, EBS, CloudWatch 등: 약 $1
- **합계: 약 5 ~ 8 USD**

## 진행 권장 순서

```
10 → 11 → 12 → 13 → 14 → 15
        Karpenter      KEDA       조합 시연      IaC
```

## 다음

→ Part 4: [PART-4-Operations](../PART-4-Operations/)
