# Part 2 — EKS 실무

## 학습 목표

EKS 클러스터를 **운영 수준에 가깝게** 구축한다. 단순 K8s를 넘어 AWS와의 통합 (네트워킹, IAM, 스토리지, 관측)을 손에 익힌다.

## 모듈 구성

| 번호 | 모듈 | 핵심 내용 |
|------|------|-----------|
| 05 | [eks-cluster-eksctl](./05-eks-cluster-eksctl/) | eksctl + ClusterConfig YAML, addon, 노드 그룹 |
| 06 | [vpc-cni-networking](./06-vpc-cni-networking/) | VPC CNI 동작, AWS Load Balancer Controller, ALB Ingress |
| 07 | [storage-irsa](./07-storage-irsa/) | EBS CSI Driver, IRSA, Pod Identity |
| 08 | [observability](./08-observability/) | CloudWatch Container Insights, kube-prometheus-stack |
| 09 | [msa-deploy](./09-msa-deploy/) | 시나리오 MSA 앱 5종을 EKS에 배포 |

## 선행 지식

- Part 1 완료 (Pod, Service, ConfigMap, RBAC, Helm 익숙)
- `00-prerequisites/` 의 ECR 푸시 완료 (또는 Part 2 진행 중 수행)

## Part 2 공용 클러스터

Part 2 부터는 클러스터를 **ClusterConfig YAML** 로 관리합니다. 모듈 05 lab에서 `eks-study-cluster.yaml` 을 만들고, 이후 모든 모듈에서 같은 클러스터를 사용.

- 이름: `eks-study`
- 리전: `ap-northeast-2`
- 노드 그룹: 관리형 + Spot 우선 (비용 절감)
- 1.35 버전, OIDC provider 활성화 (IRSA를 위해)

**비용**: 시간당 약 0.15 USD (Control Plane $0.10 + Spot 노드 2~3대).

## 예상 비용 (Part 2 전체)

- 5개 모듈 × 평균 2시간 = 10시간 학습 가정
- EKS Control Plane: 10 × $0.10 = $1.00
- t3.medium spot × 2대: 10 × 2 × $0.016 = $0.32
- ALB (모듈 06부터): 5시간 × $0.0225 = $0.11
- EBS gp3: ~$0.05
- CloudWatch Logs/Metrics: ~$1
- Prometheus EBS: ~$0.10
- **합계: 약 3 ~ 5 USD** (모듈 끝낼 때마다 cleanup 가정)

## 진행 권장 순서

```
05 (cluster) → 06 (network) → 07 (storage/IAM) → 08 (observability) → 09 (deploy)
                  └ 06부터는 클러스터가 떠 있어야 함
```

각 모듈은 약 1.5 ~ 2.5시간. 하루에 1~2개 모듈 페이스 권장.

## Part 2 종료 시

```bash
# 학습 종료 시 클러스터 삭제 (Part 3 시작 시 다시 만들 예정)
eksctl delete cluster --name eks-study --region ap-northeast-2
```

## 다음 단계

→ Part 3: [PART-3-Karpenter-KEDA](../PART-3-Karpenter-KEDA/) — 진정한 운영 심화 시작
