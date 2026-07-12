# Lab 01 — VPC CNI 동작 관찰

## 학습 확인 포인트

- [ ] Pod IP가 노드의 ENI에 등록된 보조 IP임을 확인했다
- [ ] Pod 수와 노드의 ENI/IP 한계 관계를 안다
- [ ] aws-node DaemonSet 의 환경변수 의미를 안다

> **🌱 핵심 개념 미리보기**
> - **CNI** (Container Network Interface): Pod에 IP 할당 + 네트워크 연결 표준 인터페이스
> - **VPC CNI**: AWS가 만든 EKS용 CNI. **Pod IP = VPC IP** 그대로 부여 (다른 K8s와 다름!)
> - **ENI** (Elastic Network Interface): EC2의 가상 네트워크 카드. AWS는 인스턴스 타입별 ENI 개수/IP 한도 제한
> - **DaemonSet**: 모든 노드에 정확히 1개씩 떠있는 Pod (aws-node가 그 예)

> **🧠 EKS의 네트워크 모델이 특별한 이유**
> 일반 K8s (예: kubeadm + flannel/calico) 의 Pod IP는 별도 가상 네트워크에서 옴 (예: 10.244.0.0/16).
> 외부에서 그 IP로 직접 접근 불가, NAT 거쳐야 함.
>
> EKS의 VPC CNI는 **Pod IP를 그대로 VPC 사설 IP** 로 함:
> ```
>   VPC: 10.20.0.0/16
>     Node A (10.20.1.5)
>       └─ Pod (10.20.1.42)   ← VPC IP! EC2처럼 라우팅 가능
>     Node B (10.20.2.7)
>       └─ Pod (10.20.2.18)
> ```
> 장점: ALB가 Pod IP로 직접 라우팅 가능, Security Group 적용 가능.
> 단점: VPC IP 풀 빨리 소모 (작은 CIDR 쓰면 곤란).

## 1. 노드와 ENI 매핑

```bash
kubectl get nodes -o wide
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=$NODE" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

# 노드의 ENI들
aws ec2 describe-network-interfaces \
  --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,PrivateIpAddress,PrivateIpAddresses[*].PrivateIpAddress]' \
  --output table
```

기대: ENI 한 개당 여러 IP (Primary + Secondary 들).

> **🧠 ENI당 IP 구조**
> ```
>   ENI eni-0abc...
>     ├─ Primary IP: 10.20.1.5  (노드 자체의 IP)
>     ├─ Secondary IP: 10.20.1.42  ← Pod에 할당
>     ├─ Secondary IP: 10.20.1.43  ← Pod에 할당
>     └─ Secondary IP: 10.20.1.44  ← 미사용 (warm pool)
> ```
> Pod 수가 늘면 → CNI가 ENI에 Secondary IP 추가 → Pod에 할당.
> ENI당 IP 한도 초과 → 새 ENI 부착 → 또 IP 추가.
> 인스턴스 타입별 ENI 개수 한도(t3.medium = 3개), ENI당 IP 한도(t3.medium = 6개) → t3.medium은 최대 ~17 Pod.

## 2. 그 노드의 Pod 들 IP 확인

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE | head -10
```

기대: 각 Pod IP가 위에서 본 ENI Secondary IP 중 하나와 일치.

> **`--field-selector`**: K8s가 지원하는 일부 필드 기반 필터. 라벨 셀렉터와 다름.
> spec.nodeName, status.phase 등 정해진 필드만 가능.

## 3. aws-node DaemonSet (VPC CNI 자체)

```bash
kubectl describe ds aws-node -n kube-system | grep -A30 'Environment:' | head -40
```

기대 환경변수 (주요):
```
WARM_ENI_TARGET=1
WARM_IP_TARGET=...
MINIMUM_IP_TARGET=...
ENABLE_PREFIX_DELEGATION=false
```

> **🧠 환경변수의 의미**
> | 변수 | 역할 | 예시 |
> |------|------|------|
> | `WARM_ENI_TARGET` | 미리 부착해둘 빈 ENI 개수 | 1 = 항상 1개의 빈 ENI 준비 |
> | `WARM_IP_TARGET` | 미리 할당해둘 빈 IP 개수 | 5 = 항상 5개 IP를 ENI에 미리 채워둠 |
> | `MINIMUM_IP_TARGET` | 최소 보유 IP 개수 | 10 = 풀에 10개 미만이면 즉시 보충 |
> | `ENABLE_PREFIX_DELEGATION` | /28 prefix 단위 IP 할당 (16개씩) | true → Pod 한도 폭증 |
>
> 트레이드오프:
> - WARM_* 크게 → Pod 시작 빠름, IP 풀 빨리 소모
> - WARM_* 작게 → IP 절약, Pod 시작 시 IP 할당 약간 지연

## 4. Pod 한계 시뮬레이션

t3.medium 기준 노드별 Pod 최대치는 약 17 (시스템 Pod 포함, prefix delegation 없음).

```bash
# Deployment를 조금씩 늘리면서 확인
kubectl create deploy stress --image=registry.k8s.io/pause:3.9 --replicas=15
kubectl rollout status deploy/stress
kubectl get pods -l app=stress -o wide | awk '{print $7}' | sort | uniq -c
# → 노드별 Pod 분포

# 더 늘려보기
kubectl scale deploy/stress --replicas=40
sleep 30
kubectl get pods -l app=stress | grep -c Running
kubectl get pods -l app=stress | grep -c Pending
```

기대: 일정 수에서 Pending 발생 (`FailedScheduling: too many pods` 또는 IP 부족).

> **🧠 왜 Pending? 원인 두 가지**
> 1. **K8s kubelet의 max-pods 한도** (인스턴스 타입별 자동 계산값. AWS가 하드코딩)
> 2. **VPC IP 풀 고갈** (ENI 한도 초과로 더 못 부착)
>
> 1번이 먼저 걸리는 게 보통. `kubectl describe node | grep allocatable.pods` 로 확인.

확인:
```bash
kubectl describe pod $(kubectl get pods -l app=stress --field-selector status.phase=Pending -o name | head -1) | tail -10
```

> **여기서 봐야 할 것**: Events 섹션의 `0/2 nodes are available: 2 Too many pods`
> = "노드 2개 다 Pod 한도 도달, 새 Pod 못 받음".

```bash
kubectl delete deploy stress
```

## 5. Prefix Delegation 활성화 (학습용)

```bash
# 환경변수 활성화
kubectl set env ds/aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true

# 재시작 (DaemonSet)
kubectl rollout restart ds/aws-node -n kube-system
kubectl rollout status ds/aws-node -n kube-system
```

이제 Pod 한계가 훨씬 커집니다 (이론적으로 t3.medium ~110 Pod).

> **🧠 Prefix Delegation 이란?**
> 기본: ENI마다 Secondary IP 1개씩 (RAM 1개씩 사는 격) → 한도 빨리 도달
> Prefix Delegation: ENI마다 /28 prefix 1개 (= IP 16개 묶음) → 한도 16배
>
> ```
>   기본 모드:  ENI 당 IP 6개  → 노드당 ~17 Pod
>   PD 모드:   ENI 당 prefix /28 (16IP) × 6개 = 96 IP → ~110 Pod
> ```
>
> **단점/주의**:
> - Nitro 시스템 EC2만 지원 (대부분 신형 OK, 구형 m4/c4 X)
> - VPC IP 더 빨리 소모 (Pod 안 떠있어도 IP 잡고 있음)
> - 보조 IP 풀 관리 미세하게 다름

원복:
```bash
kubectl set env ds/aws-node -n kube-system ENABLE_PREFIX_DELEGATION=false
kubectl rollout restart ds/aws-node -n kube-system
```

> **`kubectl rollout restart`**: 워크로드의 모든 Pod을 순차 재시작 (롤링).
> 이미지/설정 안 바꿔도 재시작 필요할 때 (env 변경 등) 유용.

## 6. 보조 IP 풀 모니터

```bash
kubectl get nodes -o json | jq '.items[].status.allocatable.pods'
```

각 노드의 K8s 가 보고하는 Pod 수용량 (위 환경변수에 따라 변함).

> **`allocatable` vs `capacity`**:
> - `capacity`: 이론상 최대 (RAM 4Gi, CPU 2000m, pods 17 등)
> - `allocatable`: 실제 사용 가능한 양 (시스템 예약분 제외 = capacity - kube-reserved - system-reserved)
>
> 스케줄러는 `allocatable` 기준으로 결정.

## 학습 확인 질문

1. AWS VPC CNI 가 만드는 Pod IP 는 K8s 의 가상 IP 인가, AWS VPC IP 인가?
2. `WARM_IP_TARGET=10` 으로 설정하면 어떤 효과?
3. Prefix Delegation 활성화의 트레이드오프는?

> **힌트**:
> 1. **VPC IP**. 그래서 ALB가 Pod IP로 직접 라우팅 가능, Security Group도 Pod 단위로 적용 가능.
> 2. ENI에 항상 빈 IP 10개 미리 채워둠. Pod 신규 생성 시 즉시 IP 할당 (지연 ↓), 대신 노드당 IP 점유량 ↑.
> 3. 장점 = Pod 한도 폭증. 단점 = VPC IP 풀 더 빨리 소모, Nitro 지원 인스턴스만 가능.

다음: [lab-02-alb-controller.md](./lab-02-alb-controller.md)
