# 이론 — Karpenter + KEDA 시나리오 설계

> **🌱 Karpenter + KEDA = "이벤트 콘서트장 + 임시 무대"**
> 평소엔 무대 (노드) 도 직원 (Pod) 도 없다 (비용 0).
> 손님 (메시지) 이 몰리면 KEDA 가 직원을 호출 → 자리가 부족하면 Karpenter 가 무대 (EC2) 까지 즉석에서 깔아주는 구조.

## 1. 흐름

```
시각  T=0
[큐 메시지 = 0]
[Pod = 0 (payment-service, scale-to-zero)]
[Karpenter 노드 = 0]
[비용 = 0/시간]

시각  T=10s   [SQS 에 메시지 1만 건 주입]
[큐 = 10000]

시각  T=30s   [KEDA 폴링]
KEDA: queueLength=10000, threshold=5 → desired = 2000 (cap 30)
KEDA: Deployment.replicas 0 → 30
30 Pod 가 Pending (기존 노드 부족)

시각  T=45s   [Karpenter 가 Pending 보고 NodeClaim 생성]
Karpenter: m5a.xlarge (4 vCPU, 16Gi) × 2대 → "충분히 들어가는 인스턴스 타입"
NodeClaim 생성 → EC2 launch

시각  T=90s   [노드 join]
Pod 들이 새 노드에 스케줄, Running

시각  T=180s  [메시지 처리 시작]
큐 길이 감소: 10000 → 8000 → 5000 → ...

시각  T=600s  [큐 = 0]
KEDA cooldown 시작 (90초)

시각  T=690s  [KEDA: replicas 30 → 0]
Pod 모두 종료

시각  T=720s  [Karpenter: 빈 노드 회수]
NodeClaim 삭제, EC2 종료

시각  T=750s
[Pod = 0, Node = 0, 비용 = 0/시간]
```

> **🧠 "시간축으로 보면 *2단 cascade* — KEDA 폴링 → Karpenter 프로비저닝"**
> 첫 Pod 가 뜨기까지 ≈ 60~90초가 정상 (폴링 + EC2 launch).
> 사용자 영향이 큰 동기 API 라면 *minReplicas=1* 로 idle 비용을 감수하거나, *warm pool* 패턴 고려.

## 2. 비용 계산

**가정**:
- m5a.xlarge spot 가격: 약 $0.05/시간
- 노드 2대 × 12분 = 0.4 시간
- 비용: 2 × 0.05 × 0.4 = **$0.04**

**같은 처리를 항상 켜둔 노드 2대 (m5a.xlarge spot) 로 한다면**:
- 24시간 × 0.05 × 2 = **$2.40/일** = **$72/월**

→ 트래픽 패턴이 burst 면 KEDA + Karpenter 가 95% 비용 절감.

> **🧠 "burst 패턴이 아니면 비용 효과 작다"**
> 트래픽이 24/7 균일하면 항상 켜둔 fixed 노드가 오히려 싸다 (Spot 회전 비용 X).
> KEDA + Karpenter 가 빛나는 건 *야간/주말 idle + 갑작스런 burst* 같은 *비대칭* 워크로드.

## 3. KEDA 의 메시지/Pod 비율 계산

- queueLength=5 → 5 메시지 당 Pod 1개 권장
- 큐=10000, threshold=5 → 2000 desired (이론)
- maxReplicaCount=30 → 30 으로 제한
- 30 Pod × 처리속도 (예: 5 msg/s/Pod) = 150 msg/s
- 10000 / 150 ≈ 67초

→ maxReplicaCount 를 어떻게 잡느냐가 처리 시간을 결정. 30 으로 한 이유:
- 노드 자원 제한 (학습용)
- payment-service 의 in-memory 처리 속도 가정

> **🧠 "maxReplicaCount = *시스템 보호 장치*"**
> 메시지 100만건이 한 번에 들어왔을 때 *Pod 가 무한 폭발* 하지 않게 막는 안전망.
> 다운스트림 (DB, 외부 API) 의 throughput 한계를 기준으로 잡는 게 합리적 — *내 Pod 가 빠르면 다른 시스템이 죽는다*.

## 4. Karpenter 의 노드 선택 로직

30 Pod (각 50m CPU, 64Mi 요청) → 총 1.5 CPU + 2 Gi 메모리.

가능한 노드 옵션:
- m5.xlarge (4 vCPU): 1대로 충분 (시스템 Pod + payment 30개)
- m5.large (2 vCPU): 2대 필요
- t3.medium (2 vCPU): 3대 필요 (작은 인스턴스)

Karpenter 는 **가장 작은 비용** 으로 만족하는 조합 선택. Spot 가격 / 가용성에 따라 동적.

> **🧠 "한 대 큰 노드 vs 여러 작은 노드 — 상황 따라 다르다"**
> 한 대 m5.xlarge 가 *가격* 으로는 효율적이지만, *Spot 회수 시 영향 범위* 가 커진다.
> 안정성 우선이면 작은 노드 여럿, 비용 우선이면 큰 노드 하나 — workload 의 fault-tolerance 가 기준.

## 5. 관찰 포인트

이 시나리오에서 보고 싶은 것:
1. **KEDA 의 응답 속도** — 메시지 도착 → Pod 시작 까지 (목표 < 60초)
2. **Karpenter 의 응답 속도** — Pending → 노드 Ready 까지 (목표 < 90초)
3. **End-to-end 메시지 처리 시간** — 전체 1만건 처리 시간
4. **비용** — 처리에 든 정확한 EC2 시간

> **🧠 "응답 속도 < 60s, 90s 는 *추측이 아니라 측정*"**
> 환경 / 인스턴스 타입 / AMI cache 상태에 따라 실제 시간은 크게 변한다.
> 자동 스케일링을 운영에 도입할 때는 *내 환경에서의 실측치* 를 기준으로 SLA / 알람을 잡아라 — 일반 평균을 그대로 쓰지 마라.

## 6. 메트릭 시각화

Module 08 의 Grafana 사용:
- "Kubernetes / Compute Resources / Namespace (Pods)" 대시보드
- 또는 직접 PromQL:
  - Pod 수: `count(kube_pod_info{namespace="order",created_by_name=~"payment-service"})`
  - Node 수: `count(kube_node_info)`
  - 큐 길이: KEDA 가 노출하는 external metric (또는 CloudWatch metric `ApproximateNumberOfMessages`)

> **🧠 "3선 (큐 길이 / Pod 수 / Node 수) 을 한 패널에"**
> 시간축에서 *큐 → Pod → Node 순서로 cascade* 하는 패턴을 시각화하면 어디서 지연이 생기는지 즉시 보인다.
> 단독 그래프로 보면 "KEDA 가 늦은 건지 Karpenter 가 늦은 건지" 식별 불가 — 반드시 같은 시간축에 겹쳐라.

다음: [lab-01-setup.md](./lab-01-setup.md)
