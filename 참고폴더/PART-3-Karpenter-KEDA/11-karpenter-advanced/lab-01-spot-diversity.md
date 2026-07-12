# Lab 01 — Spot 다양화 + On-Demand Fallback

## 학습 확인 포인트

- [ ] 두 NodePool (spot 우선 + ondemand fallback) 작동
- [ ] Karpenter 가 다양한 인스턴스 타입을 동시 고려
- [ ] AZ 분산 확인

> **🌱 핵심 개념 미리보기**
> - **NodePool weight**: 여러 NodePool 중 우선순위. 높을수록 먼저 시도 → Spot 100, OnDemand 10 이면 Spot 먼저.
> - **인스턴스 다양화 (diversification)**: NodePool 의 `requirements` 에 여러 family/size 허용 → Spot 회수 시 대체 풀 넓음.
> - **capacity-type**: `spot` / `on-demand` 두 값. 한 NodePool 에 둘 다 두면 가격 우선 fallback 가능.
> - **AZ 분산**: `topology.kubernetes.io/zone` requirement 로 AZ 강제 분포. 한 AZ Spot 회수에도 생존.
> - **fallback**: 우선순위 NodePool 이 한도/실패 시 자동으로 다음 NodePool.

## 1. 분리된 NodePool 적용

```bash
# 모듈 10 의 default NodePool 제거
kubectl delete nodepool default --ignore-not-found

# 새 NodePool 적용
kubectl apply -f manifests/nodepool-tiered.yaml
kubectl get nodepool
```

> **🧠 NodePool 을 두 개로 쪼개는 이유**
> 한 NodePool 에 spot+ondemand 를 같이 둘 수도 있지만, 분리하면 weight/limits/disruption 정책을 따로 줄 수 있음.
> 예: spot 은 expireAfter 짧게 (자주 회전), ondemand 는 길게 (안정성).
> Karpenter 는 weight 높은 풀부터 시도하고, requirements/limits 막히면 다음 풀.

기대:
```
NAME       NODECLASS   NODES   READY   AGE
ondemand   default     0       True    10s
spot       default     0       True    10s
```

## 2. inflate Deployment 다시 사용 (모듈 10 의 manifest)

```bash
kubectl apply -f ../10-karpenter-install/manifests/inflate-deployment.yaml
kubectl scale deploy inflate --replicas=10
```

(`nodeSelector: managed-by: karpenter` → 두 NodePool 모두 매칭)

## 3. 노드 분포 확인

```bash
sleep 90
kubectl get nodes -L nodepool,topology.kubernetes.io/zone,node.kubernetes.io/instance-type \
  | grep karpenter
```

기대 (예시):
```
ip-10-20-1-x  spot       ap-northeast-2a  c5a.large
ip-10-20-2-y  spot       ap-northeast-2b  m6a.large
ip-10-20-3-z  spot       ap-northeast-2c  t3a.large
```

→ 다른 AZ + 다른 instance family 자동 분산.

> **🧠 다양화가 Spot 안정성의 핵심**
> AWS Spot 회수는 보통 특정 (instance-type, AZ) 조합에 집중. 한 풀에 c5.large/2a 만 있으면 그 풀 회수 시 전멸.
> requirements 에 family `[c5,c5a,m5,m6a,t3a]` × size `[large,xlarge]` × zone 3개 허용하면 → 30+ 풀에 분산.
> Karpenter 는 자동으로 가장 싼 풀 + 회수율 낮은 조합 우선 선택.

## 4. Spot 가격 정보 확인

Karpenter 가 가격 데이터를 어떻게 가지고 있는지:
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 \
  | grep -i 'price\|spot' | head -10
```

또는 가격 API 직접:
```bash
aws ec2 describe-spot-price-history \
  --instance-types c5.large c5a.large m5.large m6a.large \
  --product-descriptions "Linux/UNIX" \
  --start-time $(date -u -v-1H +%FT%TZ) \
  --query 'SpotPriceHistory[*].[InstanceType,AvailabilityZone,SpotPrice]' \
  --output table | head -20
```

> **🧠 Karpenter 가 가격 정보를 갖는 방식**
> Controller 가 주기적으로 EC2 `DescribeSpotPriceHistory` 와 OnDemand pricing API 호출 → 메모리 캐시.
> 그래서 신규 인스턴스 타입 출시되거나 가격 급변 시 약간 지연 (수 분).
> Spot 가격은 AZ 별로 다름 → AZ 분산이 가격 최적화에도 유리.

## 5. On-Demand fallback 강제 시뮬레이션

Spot 만 가능한 상태에서 Spot 을 못 받게 하면 → On-Demand NodePool 로 fallback.

(실제로 Spot 부족을 만들기는 어렵지만, NodePool 의 weight 차이로 우선순위 확인 가능)

```bash
# spot NodePool 의 limits 를 0 으로 줄여 Spot 을 못 만들게 함
kubectl patch nodepool spot --type=merge -p '{"spec":{"limits":{"cpu":"0"}}}'

# 스케일 늘리기
kubectl scale deploy inflate --replicas=15
sleep 60

# 새 노드는 ondemand NodePool 에서
kubectl get nodes -L nodepool,capacity-type | grep karpenter
```

기대: 신규 노드의 `nodepool=ondemand`, `capacity-type=on-demand`.

> **🧠 fallback 트리거 조건**
> Karpenter 는 ① limits 도달 ② requirements 매칭 인스턴스 풀 모두 InsufficientCapacity ③ NodePool 이 disabled — 이 경우 다음 weight 의 NodePool 시도.
> 단순 Spot 가격 비싸짐만으로는 fallback 안 됨. limits/capacity 가 명시 신호여야 함.
> 운영에서는 spot limits 를 cluster 전체 capacity 의 80% 정도로 두고 ondemand 를 안전망으로 두는 패턴.

원복:
```bash
kubectl patch nodepool spot --type=merge -p '{"spec":{"limits":{"cpu":"100"}}}'
```

## 6. 정리

```bash
kubectl scale deploy inflate --replicas=0
sleep 60
kubectl get nodes -L nodepool | grep karpenter      # 모두 회수되어 비어야 함
```

## 학습 확인 질문

1. `weight: 100` (spot) 과 `weight: 10` (ondemand) 의 효과는?
2. instance-family 를 `[c5, m5]` 만으로 제한하면 안정성에 어떤 영향?
3. AZ 별로 노드를 강제 분산하려면 NodePool 외에 어떤 K8s 기능을 같이 써야 하나? (힌트: topologySpreadConstraints)

다음: [lab-02-disruption.md](./lab-02-disruption.md)
