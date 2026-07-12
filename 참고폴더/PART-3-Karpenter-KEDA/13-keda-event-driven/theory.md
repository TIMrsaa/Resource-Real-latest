# 이론 — Event-Driven Scaling

> **🌱 Event-Driven 스케일링 = "택배 분류센터의 동적 인력 배치"**
> 컨베이어 (큐/토픽) 에 박스 (메시지) 가 쌓이는 만큼 직원 (Pod) 을 호출, 쌓인 박스가 줄면 직원도 자동 퇴근.
> SQS 는 *바구니에 박스 몇 개?* (메시지 수), Kafka 는 *컨베이어가 직원보다 얼마나 앞섰지?* (lag) 를 기준으로 판단.

## 1. SQS Scaler 동작

```
[KEDA Operator] ─ 폴링 ──→ [SQS Queue]
       │                      ApproximateNumberOfMessages
       ▼
   threshold 와 비교 → desired replicas 계산 → HPA external metric
```

**핵심 메트릭**: `ApproximateNumberOfMessages` (SQS 의 GetQueueAttributes API).
- threshold=5, queue=50 → 50/5 = 10 replicas 권장
- maxReplicaCount 가 상한.

**ScaledObject 예시**:
```yaml
triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: keda-trigger-auth-aws
    metadata:
      queueURL: https://sqs.ap-northeast-2.amazonaws.com/123456789012/payments
      queueLength: "5"
      awsRegion: ap-northeast-2
      identityOwner: operator    # Operator 의 IRSA 사용
```

> **🧠 "`queueLength` 가 *임계* 가 아니라 *Pod 당 처리량 기대치*"**
> queueLength=5 는 "메시지 5개당 Pod 1개" 라는 의미 — 큐에 100개면 20개 Pod 권장.
> 처리 능력이 낮은 워커는 작게 (queueLength=2), 빠른 워커는 크게 (queueLength=20) — 워커 성능 기준으로 정해라.

## 2. Kafka Scaler 동작

```
[KEDA Operator] ─ 폴링 ──→ [Kafka Broker]
       │                  consumer-group lag (offset 차이)
       ▼
   lagThreshold 비교 → replicas 계산
```

**핵심 메트릭**: 컨슈머 그룹의 **lag** (가장 최근 produced offset - 컨슈머의 committed offset).
- lagThreshold=10, lag=200 → 20 replicas 권장
- 단, **partition 수 ≤ replicas 한계** (partition 수보다 많은 컨슈머는 idle)

**ScaledObject**:
```yaml
triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka.kafka:9092
      consumerGroup: notification-service
      topic: notifications
      lagThreshold: "10"
      offsetResetPolicy: latest
```

> **🧠 "Kafka 컨슈머 수의 절대 상한은 partition 수"**
> 토픽이 partition 10개라면 컨슈머는 11개부터 *그 이상은 idle* — Pod 만 늘 뿐 처리량은 안 늘어난다.
> 트래픽 폭증 대비가 필요하면 *처음부터 partition 을 넉넉히* (예: 50~100) 잡아두는 게 정답.

## 3. IRSA + KEDA TriggerAuthentication

KEDA 가 SQS 호출하려면 IAM 권한 필요. 두 가지 방식:

### 3.1 Operator 의 IAM Role 사용 (`identityOwner: operator`)

KEDA Operator Pod 의 SA 에 IRSA → 모든 SQS scaler 가 그 권한 사용.
간단하지만 한 IAM Role 이 모든 큐 접근 권한 필요.

### 3.2 워크로드의 IAM Role 사용 (`identityOwner: pod`)

워크로드 Pod 의 SA + KEDA TriggerAuthentication 으로 매핑. 큐별 권한 분리 가능.

본 lab 은 1번 (operator) 방식.

> **🧠 "operator 방식 vs pod 방식 = 운영 단순성 vs 권한 분리"**
> operator 방식은 단일 IAM Role 로 모든 큐 접근 — 학습/소규모에 적합.
> 운영 환경에서 *서비스마다 다른 큐* 면 pod 방식으로 권한 분리하는 게 보안상 정답.

## 4. KEDA Operator 에 IRSA 부여 (SQS 권한)

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=keda \
  --name=keda-operator \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess \
  --override-existing-serviceaccounts \
  --approve
```

→ KEDA Operator Pod 가 SQS GetQueueAttributes 호출 가능.

> **🧠 "KEDA 에 필요한 권한은 *읽기만* — Receive/Delete 권한은 워크로드가"**
> KEDA 는 큐 길이만 보면 되므로 `GetQueueAttributes` 만으로 충분, FullAccess 는 위험.
> ReadOnly Policy 로 KEDA 권한을 최소화하는 게 보안상 깔끔.

## 5. payment-service 도 SQS 권한 필요

KEDA 가 큐 길이 보고 Pod 늘려도, **Pod 자체** 가 메시지를 ReceiveMessage / DeleteMessage 하려면 자기 IRSA 가 또 필요. 별도 SA + IRSA.

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=order \
  --name=payment-service \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  --override-existing-serviceaccounts \
  --approve
```

(Module 09 에 미리 SA 가 있고 placeholder 어노테이션이 있었음 — 이제 실제 IRSA 적용)

> **🧠 "관측 (KEDA) 권한과 처리 (Workload) 권한은 *반드시 분리*"**
> KEDA 가 메시지 삭제 권한을 갖는 건 의미 없고 위험 — 단지 *큐가 얼마나 차 있는지* 만 알면 된다.
> 이 *Pod 마다 다른 IRSA* 패턴이 K8s 보안의 표준 — 한 Role 에 모아두지 마라.

## 6. Kafka in-cluster — Strimzi Operator

EKS 안에 Kafka 를 쉽게 띄우려면 **Strimzi**:
```bash
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  -n kafka --create-namespace --set watchAnyNamespace=true

# Kafka 클러스터 생성 (KRaft 모드, 단일 노드 학습용)
kubectl apply -n kafka -f - <<'EOF'
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role
  labels:
    strimzi.io/cluster: my-cluster
spec:
  replicas: 1
  roles: [controller, broker]
  storage:
    type: persistent-claim
    size: 10Gi
    deleteClaim: true
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-cluster
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.7.0
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF
```

→ in-cluster `my-cluster-kafka-bootstrap.kafka:9092` 로 접근 가능.

> **🧠 "in-cluster Kafka 는 학습용 — 운영하려면 *데이터 안전* 이 별도 과제"**
> EBS persistent-claim 위에 띄워도 *클러스터 자체가 망가지면 데이터 복구가 까다롭다*.
> 학습용 PoC 또는 ephemeral 워크로드면 충분하지만, 실사용 데이터를 다루면 운영 Kafka (MSK / Confluent) 가 맞다.

## 7. 운영 환경 — MSK 권장

학습은 in-cluster Kafka, 운영은 **AWS MSK** 권장:
- 클러스터 외부 (VPC 같음)
- AWS 가 운영 (패치, 백업)
- KEDA Kafka scaler 가 동일하게 사용 (bootstrapServers 만 변경)

> **🧠 "MSK 의 가치는 *운영 부담 0* 이지 *성능* 이 아니다"**
> 성능만 따지면 self-managed 가 더 빠를 수도 있지만, 새벽에 broker 가 죽으면 본인이 일어나야 한다.
> MSK 는 *내가 자는 동안 AWS 가 돌봐줌* — 그 가치가 비용을 정당화하는 경우가 대부분.

다음: [lab-01-sqs.md](./lab-01-sqs.md)
