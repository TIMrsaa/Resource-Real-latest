# 흔한 함정 5선 — 14. Combo 시나리오

## 1. 메시지 주입은 됐는데 Pod 안 늘어남

**원인 후보**:
- KEDA Operator IRSA 누락 (SQS 권한 없음)
- ScaledObject 의 큐 URL 오타 (account ID, region)
- 큐 길이 메트릭 폴링 주기 (`pollingInterval`) 가 너무 김

**진단**:
```bash
kubectl logs -n keda -l app=keda-operator --tail=50 | grep -iE 'sqs|queue|denied'
kubectl describe scaledobject -n order payment-service
```

---

## 2. Pod 는 늘었는데 Karpenter 가 노드 안 만듦

**원인 후보**:
- NodePool 의 limits 도달
- Pod 의 nodeSelector 와 NodePool 의 라벨 불일치
- EC2NodeClass NotReady (서브넷/SG 태그 누락)

**진단**:
```bash
kubectl get nodepool
kubectl describe ec2nodeclass default
kubectl describe pod -n order $(kubectl get pods -n order -l app.kubernetes.io/name=payment-service --field-selector status.phase=Pending -o name | head -1)
```

---

## 3. 메시지 처리 속도가 너무 느림

**원인 후보**:
- payment-service 의 `Handler` 가 동기 + 무거움 (인-메모리 만으로도 lock 경합)
- maxReplicaCount 가 너무 작음
- SQS visibility timeout 짧아 같은 메시지 재수신

**해결**:
- maxReplicaCount 늘리기 (단 노드 자원 한계 고려)
- payment-service 의 SQS receive 배치 사이즈 늘리기 (`MaxNumberOfMessages: 10`)

---

## 4. 처리 끝났는데 Pod 안 줄어듦

**원인 후보**:
- KEDA cooldown 진행 중 (정상)
- 큐의 ApproximateNumberOfMessages 가 0 인데 NotVisible 메시지 (in-flight) 가 있음 → ApproximateNumberOfMessages*Visible* 메트릭 사용 고려
- KEDA 폴링 빈도 (`pollingInterval`) 너무 김

**진단**:
```bash
aws sqs get-queue-attributes --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --query 'Attributes' --output table
```

---

## 5. 시연 후 EC2 비용이 예상보다 큼

**원인 후보**:
- Karpenter NodePool 의 expireAfter 가 짧아 자주 회전 → launch 비용 누적 (분 단위 청구지만 기록상 인스턴스 많음)
- 인스턴스 타입이 큰 게 자꾸 선택됨 (NodePool 의 instance-cpu 제한 미설정)
- ondemand fallback 발생

**해결**:
```bash
# 어떤 타입이 가장 많이 launch 됐는지
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=spot,ondemand" \
  --query 'Reservations[].Instances[].InstanceType' --output text \
  | tr '\t' '\n' | sort | uniq -c
```

NodePool requirements 의 `instance-cpu`, `instance-family` 좁혀서 작은 인스턴스 만 허용.
