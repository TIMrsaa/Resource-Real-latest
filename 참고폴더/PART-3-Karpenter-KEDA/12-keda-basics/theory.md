# 이론 — KEDA

> **🌱 KEDA = "손님 줄 길이에 따라 직원을 부르는 호출벨"**
> HPA 는 *직원 (Pod) 의 땀 (CPU)* 만 보고 늘리지만, KEDA 는 *손님 줄 (큐 메시지 수)* 자체를 직접 보고 늘린다.
> 손님이 0 이면 직원 0 명 (scale-to-zero), 갑자기 200명 와도 자동 호출 — 이벤트 기반 워크로드의 정석.

## 1. HPA 의 한계

K8s 기본 **HorizontalPodAutoscaler** 가 잘 못하는 것:
- **Scale to zero** — `minReplicas: 1` 이 최소. 0 까지 못 줄임
- **이벤트 기반** — CPU/Memory 외에 큐 길이, Topic lag 같은 외부 지표 직접 사용 어려움
- 커스텀 메트릭은 metrics-server / prometheus-adapter 등 추가 컴포넌트 필요 + 복잡

> **🧠 "CPU 기반 HPA 는 *증상* 을 따라가지만, 이벤트 기반은 *원인* 을 따라간다"**
> CPU 가 오를 때면 이미 대기열이 길어졌다는 *사후 신호* — HPA 가 대응할 땐 사용자가 이미 느림을 체감.
> 큐 길이 / Topic lag 자체를 보면 *사용자 영향 전에* 미리 늘릴 수 있다.

## 2. KEDA 가 채우는 것

> Kubernetes Event-Driven Autoscaling

- **scale-to-zero** 가 기본 (`minReplicaCount: 0`)
- **50+ scalers**: AWS SQS, Kafka, RabbitMQ, Prometheus, Redis, MySQL, Cron, ...
- HPA 를 **자동 생성** — 내부적으로 HPA 의 external metrics 모드 사용
- 운영 부담 낮음 — KEDA Operator 1개 + ScaledObject CRD 만

> **🧠 "KEDA = HPA 를 대체 X, *확장* O"**
> KEDA 가 HPA 를 자동 생성/관리해서 *KEDA + HPA 가 한 짝* 으로 동작한다.
> 그래서 KEDA 를 쓴다고 HPA 지식이 무의미해지는 게 아니라 *HPA 가 더 강력해진다* — kubectl get hpa 도 여전히 유효.

## 3. 동작 원리

```
┌──────────────────────────────────────────────────────┐
│  KEDA Operator (Deployment)                          │
│   ├── controller — ScaledObject reconcile            │
│   └── metrics-server — HPA가 메트릭 가져갈 source     │
└──────────────────────────────────────────────────────┘
              │ (관찰)            │ (제공)
              ▼                    ▲
    [ScaledObject CRD]      [HPA (자동 생성)]
              │                    │
              │ scaleTarget         │ scaleTargetRef
              ▼                    ▼
        [Deployment "X"]
              │
              ▼
         [Pod 들]
```

KEDA Operator 가 외부 시스템(SQS, Prometheus 등) 메트릭을 폴링 → HPA 의 external metrics 로 노출 → HPA 가 그 값으로 Pod 수 결정.

**Scale-to-zero 메커니즘**: replicas == minReplicaCount(0) 일 때 KEDA 가 직접 Deployment.spec.replicas 를 0 으로. 이벤트 발생 시 다시 1+ 로 끌어올림.

> **🧠 "scale-to-zero 는 idle 비용을 *진짜 0* 으로 만드는 유일한 길"**
> minReplicas=1 만 해도 시간당 1개 Pod 비용 (그리고 그 Pod 가 점유한 노드 비용) 이 발생.
> 야간 / 주말 / 트래픽 없는 워크로드는 0 으로 떨어지면 *노드까지 회수* 되어 진짜 비용 0 가능.

## 4. ScaledObject CRD 기본 구조

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: my-scaler
spec:
  scaleTargetRef:
    name: my-app                          # Deployment 이름
  minReplicaCount: 0
  maxReplicaCount: 50
  pollingInterval: 30                     # 초당 외부 메트릭 폴링
  cooldownPeriod: 300                     # 5분 동안 트리거 0 이면 0 으로 축소
  triggers:
    - type: cpu
      metadata:
        type: Utilization
        value: "70"
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: http_requests_per_second
        threshold: "100"
        query: sum(rate(http_requests_total[1m]))
```

여러 trigger 동시 가능 — OR 로직 (어느 하나 임계 넘으면 scale up).

> **🧠 "cooldownPeriod 가 짧으면 Pod 가 펄럭댄다"**
> 메시지가 잠깐 비었다고 즉시 0 으로 떨어지면, 다음 메시지가 들어올 때 cold start 가 반복돼 latency 폭증.
> 워크로드 특성에 따라 5분 (300s) ~ 10분 정도가 안정적 — 너무 짧게 잡지 마라.

## 5. ScaledJob — Job 용

ScaledObject 는 Deployment / StatefulSet 대상. **단발성 작업** (큐 메시지 처리 등) 은 ScaledJob:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: process-queue
spec:
  jobTargetRef:
    template:
      spec:
        containers:
          - name: worker
            image: my-worker:v1
        restartPolicy: Never
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: ...
        queueLength: "1"
```

→ 큐에 메시지 N 개 → Job N 개 자동 생성 → 처리 끝나면 사라짐.

> **🧠 "ScaledObject = 상시 워커, ScaledJob = 일회성 작업"**
> 메시지를 *계속 처리* 하는 워커 (consumer loop) 면 ScaledObject.
> 메시지 1건 = 작업 1번 (DB 마이그레이션, 비디오 인코딩) 처럼 *유한 작업* 이면 ScaledJob — 끝나면 자동으로 사라져서 GC 부담 없음.

## 6. TriggerAuthentication — 자격증명 분리

Trigger 가 외부에 인증 필요할 때 (AWS / DB 등):

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-sqs-auth
spec:
  podIdentity:
    provider: aws        # IRSA 사용
```

ScaledObject 에서 참조:
```yaml
triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: aws-sqs-auth
    metadata:
      queueURL: ...
      identityOwner: operator   # KEDA Operator 의 IAM Role 사용
```

본 lab 모듈 13 에서 본격적으로 다룸.

> **🧠 "TriggerAuth 가 *Trigger 자체에 credential 박는* 안티패턴을 막는다"**
> ScaledObject 에 AccessKey 를 박으면 *모든 ScaledObject 가 그 credential 을 공유* — 분리되지 않은 신뢰 영역.
> TriggerAuth + IRSA 조합으로 *각 ScaledObject 가 자기만의 IAM Role* 을 갖게 하는 게 정답.

## 7. KEDA + Karpenter 시너지 (Module 14 의 핵심)

```
[SQS 메시지 폭증]
    ↓
[KEDA] Pod 0 → 50 으로 빠르게 스케일
    ↓
[K8s scheduler] 50 개 Pod 모두 스케줄 시도
    ↓
[일부 Pending] (기존 노드 부족)
    ↓
[Karpenter] Pending 보고 Spot 노드 즉시 추가
    ↓
[Pod 모두 Running]
    ↓
[메시지 처리 완료]
    ↓
[KEDA] Pod 50 → 0 (cooldown 후)
    ↓
[Karpenter] 빈 노드 회수
```

→ **인프라 비용은 처리량에 비례** (기본 시간엔 0).

> **🧠 "KEDA 는 Pod 를, Karpenter 는 Node 를 — 각자 자기 레이어"**
> 둘이 같은 메트릭을 보지 않아도 자연스럽게 협업한다 (KEDA → Pending Pod → Karpenter).
> 그래서 *KEDA 설정 / Karpenter 설정을 따로 고민* 하면 되고, 둘을 묶는 별도 통합 도구가 필요 없다.

다음: [lab-01-install.md](./lab-01-install.md)
