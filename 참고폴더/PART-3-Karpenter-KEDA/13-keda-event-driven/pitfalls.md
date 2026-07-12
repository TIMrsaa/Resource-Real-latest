# 흔한 함정 5선 — 13. KEDA Event-Driven

## 1. KEDA Operator 가 SQS 호출 못 함

**증상**: SQS scaler 만들었는데 큐가 가득 차도 scale up 안 됨.

**원인**:
- KEDA Operator 의 SA 에 IRSA 안 됨
- IRSA 어노테이션 추가 후 Pod 재시작 안 함

**진단**:
```bash
kubectl get sa -n keda keda-operator -o yaml | yq '.metadata.annotations'

kubectl logs -n keda -l app=keda-operator --tail=50 | grep -iE 'sqs|denied|forbidden'
```

**해결**:
```bash
eksctl create iamserviceaccount --cluster=eks-study --namespace=keda --name=keda-operator \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess \
  --override-existing-serviceaccounts --approve

kubectl rollout restart deploy/keda-operator -n keda
```

---

## 2. partition 수 < replicas 로 over-provisioning

**증상**: Kafka scaler 가 maxReplicaCount=20 으로 늘렸는데 partition 이 3 → 17 Pod 가 idle.

**원인**: 컨슈머 그룹의 동시 활성 한계 = partition 수.

**해결**:
- maxReplicaCount 를 partition 수 이하로
- 또는 partition 수를 늘림 (`KafkaTopic` 의 `partitions` 변경 — replicaFactor 등 호환 필요)
- 학습용 Strimzi 면:
```bash
kubectl patch kafkatopic notifications -n kafka --type=merge -p '{"spec":{"partitions":10}}'
```

---

## 3. payment-service 가 SQS 메시지 처리 못 함 (Pod 자체 권한)

**증상**: KEDA 가 Pod 늘렸지만 메시지 안 줄어듦. 큐 길이 그대로.

**원인**: payment-service 의 SA 에도 IRSA 필요 (KEDA Operator 와 별도).

**진단**:
```bash
kubectl logs -n order deploy/payment-service --tail=20
# AccessDenied 에러
```

**해결**:
```bash
eksctl create iamserviceaccount --cluster=eks-study --namespace=order --name=payment-service \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  --override-existing-serviceaccounts --approve

kubectl rollout restart deploy/payment-service -n order
```

---

## 4. Kafka scaler 의 lag 0 으로 안 줄어 cooldown 영원히 안 시작

**증상**: 컨슈머 그룹이 처리 끝났는데 lag 가 양수로 보임 → KEDA 가 계속 Pod 유지.

**원인**:
- 컨슈머가 commit 안 함 (auto-commit 비활성 + manual commit 누락)
- Kafka 의 commit 지연 (offset 커밋 후 KEDA 가 갱신 보기까지 시간)

**진단**:
```bash
kubectl exec -n kafka my-cluster-kafka-0 -- bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-service
# CURRENT-OFFSET, LAG 컬럼 확인
```

**해결**: 앱이 정상적으로 commit 하는지 확인. `kafka-go` 의 `CommitMessages` 호출 누락 점검.

---

## 5. SQS 큐가 다른 리전에 있음

**증상**: KEDA 로그에 `Unable to determine endpoint`.

**원인**: ScaledObject 의 `awsRegion` 누락 또는 KEDA Operator 의 default region 과 다름.

**해결**:
```yaml
triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.us-east-1.amazonaws.com/...
      awsRegion: us-east-1     # ← 명시
```
