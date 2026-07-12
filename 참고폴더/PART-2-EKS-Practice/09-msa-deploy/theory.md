# 이론 — MSA 배포 아키텍처

> **🌱 MSA 배포 = "백화점 입점 구조"**
> ALB 는 1층 안내데스크, 각 서비스 (frontend / order / user / payment) 는 매장 한 칸씩.
> 같은 NS = 같은 백화점, 짧은 DNS = 매장 내선번호, ALB 그룹 = 한 안내데스크가 여러 매장으로 안내 — 매장 늘려도 데스크 하나만 있으면 됨.

## 1. 배포할 서비스

| 서비스 | 타입 | 외부 노출 | 내부 통신 | 외부 의존 |
|--------|------|-----------|-----------|----------|
| frontend | Deployment + Ingress | ALB (HTTP) | order, user 호출 | - |
| order-service | Deployment + Ingress | ALB (HTTP) `/api/orders` | user-service gRPC 호출 | - |
| user-service | Deployment + ClusterIP | - (내부만) | - | - |
| payment-service | Deployment | - | - | AWS SQS |
| notification-service | Deployment | - | - | Kafka (외부 또는 in-cluster) |

**디자인 결정**:
- DB 없음 — 학습 단순화 (in-memory)
- StatefulSet 안 씀 — Pod 정체성 불필요
- 외부 큐 (SQS, Kafka) 는 Part 3 에서 본격 사용

> **🧠 "외부 의존성 (SQS/Kafka) 은 IRSA 또는 외부 endpoint 둘 중 하나"**
> AWS 매니지드 서비스는 IRSA 로 IAM 권한만 주면 SDK 가 알아서 호출 — Pod 안에 credential 박을 필요 X.
> 외부 Kafka 같은 비-AWS 서비스는 외부 endpoint + Secret (TLS 인증서) 패턴 — 두 가지를 혼동하지 마라.

## 2. 토폴로지

```
         (Internet)
            │
            ▼
     ┌─── ALB (group: eks-study) ───┐
     │                               │
     │  /            → frontend      │
     │  /api/orders  → order-service │
     │  /api/users   → user-service  │ (REST 게이트웨이는 없으므로 user는 노출 안 함)
     └───────────────────────────────┘
                 │
                 ▼
        ┌─ K8s ClusterIP ─┐
        │                  │
        │  order-service ─→ user-service (gRPC :50051)
        │       │
        │  payment-service ─→ (Container Insights / Prometheus 메트릭)
        │       │
        │  notification-service
        └──────────────────┘
                 │
                 ▼
        AWS SQS, External Kafka
```

> **🧠 "외부 → ALB → ClusterIP → Pod" 가 EKS 트래픽의 표준 4단 경로**
> 이 표준에서 벗어나면 (예: Pod 가 LoadBalancer Service 로 직접 노출) 비용 + 운영 부담이 늘어난다.
> 토폴로지를 단순화하는 가장 큰 무기는 *ALB 1개로 다중 Ingress 그룹화* — 자세한 건 §4.

## 3. 공유 패턴

### 3.1 같은 NS

`order` namespace 에 5개 서비스 모두 배포 → DNS 짧은 이름 사용.

### 3.2 ECR Pull Secret 불필요

노드 IAM Role 에 `AmazonEC2ContainerRegistryReadOnly` 정책이 있으므로 Pod 가 ECR 에서 직접 pull. (Self-managed 노드 그룹에서도 노드 IAM Role 에 추가만 해주면 됨.)

### 3.3 Health check 통일

모든 서비스가 `/healthz` (메인 포트) 또는 `:9090/healthz` (메트릭 포트) 노출.

> **🧠 "공통 패턴이 운영을 살린다"**
> `/healthz` / metrics port 9090 / `release: kps` label / 같은 NS — 이런 *전 서비스가 따르는 표준* 이 trace/dashboard 자동화의 토대.
> 서비스별로 다 다르면 매번 ServiceMonitor / Ingress / NetworkPolicy 를 따로 작성해야 한다.

## 4. ALB 그룹화

여러 Ingress 가 ALB 를 공유:
```yaml
annotations:
  alb.ingress.kubernetes.io/group.name: eks-study   # 같은 그룹은 같은 ALB
  alb.ingress.kubernetes.io/group.order: "10"        # 우선순위
```

→ ALB 1개 비용으로 다중 호스트/경로 라우팅. 본 lab은 단일 그룹 사용.

> **🧠 "group.name 만 같으면 자동으로 한 ALB 에 합쳐진다"**
> Ingress 가 5개여도 group.name 만 동일하면 ALB 는 1개만 생성 — 청구서가 5분의 1.
> 다만 *우선순위 (group.order)* 가 충돌하면 라우팅이 꼬일 수 있어, 처음부터 명시적 번호 (10, 20, 30) 로 관리.

## 5. ServiceMonitor 일괄 등록

각 서비스마다 ServiceMonitor 만들 수도 있고, 공용 ServiceMonitor로 한 번에 처리도 가능.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-services
  namespace: monitoring
  labels:
    release: kps
spec:
  namespaceSelector:
    matchNames: ["order"]
  selector:
    matchLabels:
      eks-study/scrape: "true"
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
```

→ Service 에 `eks-study/scrape: "true"` 라벨만 붙이면 자동 scrape.

> **🧠 "라벨 기반 자동 등록" 이 MSA 운영의 결정적 도구"**
> 새 마이크로서비스를 추가할 때 *ServiceMonitor 를 작성할 필요 없이* 라벨만 붙이면 됨.
> Prometheus, NetworkPolicy, ServiceMesh 트래픽 룰 모두 이 *라벨 컨벤션* 위에 구축된다 — 라벨이 운영 자동화의 화폐.

## 6. Resource Sizing

학습용 가벼운 설정:

| 서비스 | requests | limits |
|--------|----------|--------|
| frontend | 50m / 64Mi | 200m / 128Mi |
| order-service | 100m / 128Mi | 500m / 256Mi |
| user-service | 100m / 128Mi | 500m / 256Mi |
| payment-service | 50m / 64Mi | 200m / 128Mi |
| notification-service | 50m / 64Mi | 200m / 128Mi |

총 requests: ~350m CPU + ~448Mi Memory → t3.medium 노드 1대로도 충분.

> **🧠 "학습용 sizing 으로 운영을 가지 마라"**
> 50m CPU 같은 작은 requests 는 학습/PoC 엔 OK 지만, 운영에선 *burst 시 throttling* + 정확한 right-sizing 부재로 위험.
> 운영 진입 시 VPA Recommendation 모드를 1주 돌려 실제 사용량 기반으로 requests 를 재산정.

다음: [lab-01-prepare.md](./lab-01-prepare.md)
