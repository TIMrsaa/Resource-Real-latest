# 이론 — VPC CNI & AWS Load Balancer Controller

> **🌱 VPC CNI = "Pod 한 명 한 명에게 회사 명함 (VPC IP) 직접 발급"**
> 다른 CNI 는 *임직원 임시 출입증* (오버레이 IP) 을 발급하지만, AWS VPC CNI 는 *진짜 회사 명함* 을 준다.
> 그래서 RDS, ALB 가 Pod 를 *VPC 안의 평범한 서버* 로 인식 — 보안그룹/라우팅 그대로 활용 가능.

## 1. K8s 네트워킹 기본 원칙

K8s 가 모든 CNI 구현체에 요구하는 것:
- 모든 Pod이 NAT 없이 서로 통신 가능
- 모든 노드가 NAT 없이 모든 Pod과 통신 가능
- Pod 자기 IP 가 다른 Pod이 보는 IP와 같음

CNI 구현은 자유 (Calico, Cilium, Flannel, ...). EKS는 **AWS VPC CNI** 가 기본.

> **🧠 "NAT 없이 통신" 이 K8s 의 마법 같은 단순함의 원천**
> 이 한 가지 원칙 덕에 *Pod IP = 다른 Pod 가 보는 IP* 가 보장된다 — 디버깅이 단순해진다.
> 만약 NAT 가 끼면 traffic 추적, health check, 보안 로그 분석이 전부 어려워진다.

## 2. AWS VPC CNI의 핵심 아이디어

> **Pod이 VPC 서브넷의 IP를 직접 받는다.**

다른 CNI는 보통 Pod에게 "오버레이 네트워크"의 가상 IP (예: 10.244.x.y)를 줍니다. AWS VPC CNI는 다릅니다 — 노드의 ENI에 보조 IP들을 할당해, **각 Pod에 진짜 VPC IP를 직접** 부여.

```
[VPC 10.20.0.0/16]
   │
   ├─ Subnet A (10.20.1.0/24)
   │    └─ EC2 Node-1 (Primary IP 10.20.1.10)
   │         ├─ ENI-1 secondary: 10.20.1.20  → Pod-A
   │         ├─ ENI-1 secondary: 10.20.1.21  → Pod-B
   │         └─ ENI-2 secondary: 10.20.1.40  → Pod-C
   │
   └─ Subnet B ...
```

### 2.1 장점

- **Pod 간 통신이 VPC 네이티브** — 보안그룹/라우팅으로 직접 제어
- **레이턴시 낮음** — 오버레이 캡슐화 없음
- **외부 AWS 서비스 호출 시** Pod IP가 그대로 보임

### 2.2 한계

- **VPC IP를 빠르게 소모** — 작은 서브넷이면 Pod 수 한계
- **노드별 Pod 한계 = ENI 수 × 보조 IP 수**
  - 예: t3.medium = 3 ENI × 5 = 15 보조 IP → 최대 ~17 Pod
  - 인스턴스 타입에 따라 표 정해져 있음

### 2.3 Prefix Delegation

ENI 의 보조 IP 1개당 /28 (16개 IP) 할당:
- t3.medium: 3 ENI × 16 prefix × 16 IP = 이론적 최대치 ↑
- 환경변수 `ENABLE_PREFIX_DELEGATION=true`

**기본 비활성**. 활성화 시 Pod 한계 ↑ but VPC IP는 더 빠르게 소모.

```bash
kubectl describe ds aws-node -n kube-system | grep -E 'WARM|ENABLE'
```

> **🧠 "Pod 가 안 뜨면 IP 부족부터 의심"**
> `InsufficientFreeAddressesInSubnet` 같은 에러는 *Subnet CIDR 이 너무 작아서* — Pod 수가 적어 보여도 ENI 의 보조 IP 가 미리 잡혀 있어 빠르게 고갈된다.
> 사전 설계: 클러스터 서브넷은 /20 (~4000 IP) 이상 권장.

## 3. WARM_IP_TARGET / WARM_PREFIX_TARGET

ENI / IP 를 미리 할당해 두는 워밍 정책:

| 변수 | 의미 |
|------|------|
| `WARM_IP_TARGET` | 사용 중 + 사용 가능 = 항상 N개 보장 |
| `MINIMUM_IP_TARGET` | 최소 보장 IP 수 |
| `WARM_ENI_TARGET` | 미리 할당해둘 ENI 수 |

대규모 동시 Pod 생성 시 IP 할당 지연 방지.

> **🧠 "WARM 이 크면 IP 낭비, 작으면 burst 가 느림"**
> Pod 가 폭증하는 워크로드 (CI 러너, 배치 잡) 는 WARM 값을 크게, 안정적 워크로드는 작게.
> 한 클러스터 안에서도 NodePool 별로 다르게 잡으면 IP 효율 + burst 대응을 모두 챙길 수 있다.

## 4. SecurityGroupsForPods (선택 기능)

Pod에 별도 보안 그룹 부여 가능 (특정 워크로드만 RDS 접근 등):
```yaml
apiVersion: vpcresources.k8s.aws/v1beta1
kind: SecurityGroupPolicy
metadata:
  name: db-access
spec:
  podSelector:
    matchLabels: { app: api }
  securityGroups:
    groupIds: [sg-xxx]
```

→ 본 커리큘럼에서는 사용하지 않지만 알아두면 유용.

> **🧠 SG-for-Pods 가 IRSA 의 네트워크 버전**
> IRSA 가 "Pod 별 IAM 권한 분리" 라면, SG-for-Pods 는 "Pod 별 보안그룹 분리".
> RDS 접근 권한을 *특정 Pod 만 허용* 하는 식으로 *워크로드 단위* 보안 경계를 그릴 수 있다.

## 5. AWS Load Balancer Controller — 왜 필요한가

EKS 의 기본 in-tree CCM:
- `type: LoadBalancer` Service → Classic LB (구식, 권장 안 함)
- Ingress 지원 ❌

AWS Load Balancer Controller 설치 시:
- `type: LoadBalancer` + 어노테이션 → NLB (현대식, IP 타겟 모드)
- `Ingress` 리소스 → ALB 자동 생성 + 설정
- TargetGroupBinding 으로 외부 ALB와 K8s Service 연결

> **🧠 "Ingress 만들고 ALB 안 뜨면 99% Controller 미설치/권한"**
> EKS 기본 in-tree CCM 은 *Ingress 를 무시한다* — AWS LB Controller 가 그 빈자리를 채운다.
> 그래서 Ingress YAML 을 만들고 ALB 가 안 만들어지면 → Controller Pod 상태 + IRSA 권한부터 점검.

## 6. ALB Target 모드: IP vs Instance

```
[ALB] → [Target Group]
            ├─ IP 모드: 직접 Pod IP 등록
            └─ Instance 모드: 노드 IP + NodePort 등록
```

**IP 모드** (권장):
- ALB가 Pod에 직접 라우팅 (kube-proxy 한 단계 제거)
- 더 적은 hop, 더 정확한 health check
- VPC CNI 가 Pod IP 를 VPC IP로 주는 덕에 가능

**Instance 모드**:
- 호환성 좋음 (다른 CNI도 가능)
- Pod 자체의 health 가 아니라 노드 health

본 커리큘럼은 IP 모드 사용.

> **🧠 IP 모드 가 가능한 이유는 VPC CNI 덕분**
> 다른 CNI 의 오버레이 IP 는 VPC 가 모르는 IP — ALB 가 그 IP 로 라우팅할 수 없다.
> VPC CNI 의 "진짜 VPC IP" 덕에 ALB 가 Pod 에 *직접* 트래픽을 꽂을 수 있다 — 두 컴포넌트가 한 짝.

## 7. AWS LB Controller 설치 흐름

1. IAM Policy 생성 (LB 만들/삭제 권한)
2. IRSA 셋업 — ServiceAccount + IAM Role 매핑
3. Helm 으로 설치 — `eks/aws-load-balancer-controller`
4. Ingress / Service 어노테이션으로 사용

> **🧠 "IAM Policy 가 변경되면 Pod 재시작 필요 없음, IRSA 만 갱신"**
> IRSA 는 토큰 기반이라 IAM Policy 만 수정하면 다음 API 호출부터 새 권한 적용된다.
> 다만 *권한이 없어서 한 번 fail* 한 컴포넌트는 backoff 로 한참 잠들어 있을 수 있어, 정책 수정 후 Pod restart 가 빠를 때도 있다.

다음: [lab-01-cni-observation.md](./lab-01-cni-observation.md)
