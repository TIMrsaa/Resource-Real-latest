# Part 1 — Kubernetes 기초

> **💡 일상 비유로 이해하기**
> 
> Kubernetes 는 **대형 쇼핑몰의 통합 관리실**과 같습니다. 입점 매장(Pod), 안내 데스크(Service), 매장 운영 지침서(ConfigMap), 출입 권한 카드(RBAC)를 한 곳에서 관리하죠. Part 1 에서는 이 관리실의 기본 도구들을 하나씩 익혀봅니다.

## 학습 목표

Kubernetes의 핵심 객체(Pod, Deployment, Service, ConfigMap, Secret, RBAC)를 이해하고, 실제 EKS 클러스터에 직접 배포해보며 손에 익힌다.

## 모듈 구성

| 번호 | 모듈 | 학습 키워드 |
|------|------|-------------|
| 01 | [core-concepts](./01-core-concepts/) | Pod, ReplicaSet, Deployment, Namespace |
| 02 | [services-networking](./02-services-networking/) | Service (ClusterIP/NodePort/LB), Ingress, CoreDNS |
| 03 | [config-storage](./03-config-storage/) | ConfigMap, Secret, PV/PVC, StatefulSet |
| 04 | [rbac-helm](./04-rbac-helm/) | ServiceAccount, RBAC, Helm 차트 |

## 선행 지식

- [`00-prerequisites/`](../00-prerequisites/) 완료
- AWS CLI 자격증명 등록됨 (`aws sts get-caller-identity` 통과)
- 로컬 도구 9종 설치됨 (`bash 00-prerequisites/scripts/check-tools.sh` 통과)

## 학습용 EKS 클러스터 (Part 1 공용)

Part 1은 작은 EKS 클러스터 한 개를 4개 모듈에서 공용으로 사용합니다.
**비용 절감을 위해 4개 모듈을 가능한 같은 날 진행하고 끝나면 즉시 삭제**하세요.

### 클러스터 생성 (모듈 01 시작 시 1회)

```bash
eksctl create cluster \
  --name eks-study \
  --region ap-northeast-2 \
  --version 1.35 \
  --node-type t3.small \
  --nodes 2 --nodes-min 0 --nodes-max 4 \
  --managed --spot
```

소요 시간: 15 ~ 20 분.
예상 비용: 시간당 약 0.13 USD (Control Plane $0.10 + spot 노드 2대).

### kubeconfig 등록

```bash
aws eks update-kubeconfig --name eks-study --region ap-northeast-2
kubectl get nodes
```

기대: 노드 2개가 `Ready` 상태로 출력.

### Part 1 종료 시 클러스터 삭제

```bash
eksctl delete cluster --name eks-study --region ap-northeast-2
```

## 예상 비용 (Part 1 전체)

- 4개 모듈 × 평균 1.5 시간 = 6 시간 학습 가정
- EKS Control Plane: 6 × $0.10 = **$0.60**
- t3.small spot × 2대: 6 × 2 × $0.007 = **$0.084**
- ALB (모듈 02 일부): 1 시간 × $0.0225 = **$0.023**
- **합계: 약 0.7 ~ 1 USD**

(매일 클러스터 삭제 후 다음 날 다시 만드는 시나리오면 비용은 더 적어집니다.)

## Part 1 종료 미니 프로젝트

[모듈 04 끝부분](./04-rbac-helm/mini-project.md):
- 시나리오 앱 `order-service` 를 Helm 차트로 패키징
- 최소 EKS 클러스터에 배포
- Service/Ingress 로 외부 노출
- HPA 적용 후 부하 발생시켜 동작 확인

## 진행 권장 순서

1. 본 README의 클러스터 생성 명령 실행
2. `01-core-concepts/` 부터 모듈별로 진행 (`README → theory → lab → quiz → pitfalls → cleanup`)
3. 4개 모듈 완료 후 미니 프로젝트
4. 학습 종료 시 즉시 클러스터 삭제

## 다음 단계

→ [01-core-concepts](./01-core-concepts/)
