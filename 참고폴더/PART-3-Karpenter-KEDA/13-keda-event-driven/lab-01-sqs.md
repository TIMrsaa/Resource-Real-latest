# Lab 01 — SQS 기반 ScaledObject

## 학습 확인 포인트

- [ ] SQS 큐 만들고 KEDA Operator 에 SQS 읽기 권한 IRSA 부여
- [ ] payment-service 가 0 → N 으로 큐 길이에 비례 스케일
- [ ] 큐 비우면 다시 0

> **🌱 이 lab 의 핵심: 진짜 이벤트 기반 스케일링**
> CPU 스케일링은 결과 지표(CPU 부하)를 보지만, 이건 **원인 지표(큐 길이)** 를 봄.
> = 부하가 오기 전에 미리 Pod 늘릴 수 있음.
>
> 시나리오:
> ```
>   주문 폭주 → SQS 큐 메시지 ↑ (1000개)
>     ↓ KEDA 감지 (~15초)
>   payment-service replicas 0 → 30
>     ↓ Karpenter 감지 (~30초)
>   노드 추가 → Pod 스케줄
>     ↓
>   메시지 처리 → 큐 비움 → KEDA가 0으로
>     ↓
>   빈 노드 회수 (Karpenter)
> ```
> = 사용한 만큼만 비용. 평소 0원, 폭주 시만 비례 비용.

## 1. SQS 큐 생성

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

aws sqs create-queue --queue-name eks-study-payments --region $REGION

QUEUE_URL=$(aws sqs get-queue-url --queue-name eks-study-payments --query QueueUrl --output text)
echo $QUEUE_URL
```

> **🧠 SQS 기본 옵션**
> - **Standard Queue** (기본): 고처리량, At-Least-Once, 순서 보장 X
> - **FIFO Queue** (`.fifo` 접미사): 순서 보장, Exactly-Once, 처리량 ↓ (300 msg/s)
>
> 결제처럼 중복이 치명적이면 FIFO. 본 lab은 학습용이라 Standard.

## 2. KEDA Operator 에 SQS 권한 IRSA

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=keda \
  --name=keda-operator \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess \
  --override-existing-serviceaccounts \
  --approve --region=$REGION

# Pod 재시작 (SA annotation 새로 반영)
kubectl rollout restart deploy/keda-operator -n keda
kubectl wait --for=condition=available deploy/keda-operator -n keda
```

> **🧠 왜 ReadOnly 권한만 부여하나?**
> KEDA Operator는 큐 길이 조회만 함 (`GetQueueAttributes`). 메시지 수신/삭제 X.
> 메시지 처리는 Pod (payment-service) 가 자기 IRSA로 직접.
> = 최소 권한 원칙 (Operator가 메시지 망가뜨릴 위험 X).

## 3. payment-service 의 SA 에 IRSA (Pod 도 SQS 호출 가능해야)

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=order \
  --name=payment-service \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  --override-existing-serviceaccounts \
  --approve --region=$REGION
```

> **`AmazonSQSFullAccess`** vs ReadOnly: payment-service Pod은 메시지 받기/삭제 필요.
> 운영에선 큐별로 정책을 좁히는 게 권장 (`Resource: arn:aws:sqs:...:eks-study-payments` 만 허용).

## 4. payment-service Deployment 의 env 갱신 (실제 큐 URL 로)

```bash
kubectl set env deploy/payment-service -n order \
  SQS_QUEUE_URL=$QUEUE_URL \
  AWS_REGION=$REGION
```

`kubectl rollout status deploy/payment-service -n order` 로 새 Pod 가 떠 있는지 확인 (이전엔 placeholder URL 로 CrashLoop 였을 수 있음).

> **`kubectl set env`**: Deployment의 env 즉시 변경 + 자동 rollout 트리거.
> 같은 효과: `kubectl edit deploy/payment-service -n order` 로 spec 수정.

## 5. ScaledObject 적용

```bash
sed "s|ACCOUNT_ID|${ACCOUNT_ID}|g" manifests/sqs-scaledobject.yaml \
  | kubectl apply -f -

kubectl get scaledobject -n order
```

> **`sed` 트릭**: YAML 안의 `ACCOUNT_ID` 문자열을 실제 ID로 치환. `|` 를 구분자로 (URL의 `/` 충돌 방지).
> 운영에선 Helm/Kustomize/envsubst 사용.

## 6. payment-service 가 0 으로 줄어드는 것 관찰

```bash
watch -n3 'kubectl get hpa -n order; kubectl get pods -n order -l app.kubernetes.io/name=payment-service'
```

기대 (1~2분 후 큐가 비어있으니):
```
HPA TARGETS         REPLICAS
... 0/5 (avg)       0      ← scale-to-zero
```

> **🧠 0으로 가는 흐름**
> 1. KEDA가 SQS 폴링 → 메시지 0개
> 2. ScaledObject의 `minReplicaCount: 0` 이라 0까지 허용
> 3. cooldownPeriod(90초) 동안 메시지 안 들어오면 → 0
> 4. HPA가 Deployment를 0으로 → Pod 모두 종료
>
> **Pod 0 vs replicas 0 차이**: Deployment의 spec.replicas는 0으로 변경됨. ScaledObject가 관리하는 동안엔 사용자가 manual scale 하지 말 것 (충돌).

## 7. 큐에 메시지 1000건 주입 → Pod 폭발

```bash
echo "Sending messages..."
for i in $(seq 1 1000); do
  aws sqs send-message --queue-url $QUEUE_URL \
    --message-body "{\"order_id\":\"o-$i\",\"amount\":$((RANDOM % 1000))}" \
    > /dev/null &
  if (( i % 50 == 0 )); then wait; fi
done
wait
echo "Done."
```

> **`&` + `wait` 패턴**: 50개씩 병렬 전송. 한꺼번에 1000개 호출하면 AWS API throttle 걸림.

watch 화면:
```
HPA TARGETS         REPLICAS
... 1000/5 (avg)    30     ← maxReplicaCount 도달
```

(1000/5 = 200 desired, max 30 으로 제한)

> **🧠 desired Pod 수 계산**
> KEDA의 SQS scaler:
> ```
>   desired = ceil(메시지수 / queueLength)
> ```
> queueLength=5, 메시지=1000 → ceil(1000/5) = 200.
> 하지만 `maxReplicaCount: 30` 에 의해 30으로 제한됨.
>
> **trade-off**: queueLength 작게 → Pod 더 많이 (처리 빠름), Pod 시작 오버헤드 ↑.
>             queueLength 크게 → Pod 적게 (효율적), 처리 시간 ↑.

## 8. Pod 들이 메시지 처리

```bash
kubectl logs -n order -l app.kubernetes.io/name=payment-service --tail=20 --prefix=true
```

기대: 각 Pod 가 메시지 받아 "processed payment" 로그 남김.

> **`--prefix=true`**: 로그 라인마다 Pod 이름 prefix. 여러 Pod 동시 모니터링 시 구분 가능.

큐 잔여량 모니터:
```bash
watch -n5 "aws sqs get-queue-attributes --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' --output text"
```

처리되면서 0 으로 감소.

> **`Approximate` 가 붙은 이유**: SQS는 분산 시스템 → 정확한 카운트 X. 약 ±10초 지연. 작은 큐엔 정확하지만 큰 큐엔 ±수십.

## 9. 처리 완료 후 자동 축소

큐가 비면 → KEDA cooldown 90초 후 → 0 으로.

## 10. 정리

```bash
kubectl delete -f manifests/sqs-scaledobject.yaml --ignore-not-found
aws sqs delete-queue --queue-url $QUEUE_URL
```

> **SQS는 빈 큐 비용 미미** (시간당 수 센트). 그래도 학습 끝나면 삭제 권장.

## 학습 확인 질문

1. KEDA Operator 의 IRSA 와 payment-service Pod 의 IRSA 가 별도인 이유는?
2. queueLength=5, max=30 일 때 큐에 100 메시지 있으면 desired Pod 수는?
3. SQS 의 `ApproximateNumberOfMessages` 는 정확한가?

> **힌트**:
> 1. 최소 권한 원칙. Operator는 큐 길이만 조회(read-only), Pod은 메시지 수신/삭제(read-write). 권한 분리.
> 2. ceil(100/5) = 20. max=30 미만이라 20개 그대로 띄움.
> 3. 분산 시스템이라 약간 부정확 (수~수십 차이). 작은 큐(<100)면 거의 정확. KEDA는 이 값 그대로 사용 → 짧은 spike엔 약간 늦게 반응.

다음: [lab-02-kafka.md](./lab-02-kafka.md)
