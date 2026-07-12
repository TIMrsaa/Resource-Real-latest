# 퀴즈 — 13. KEDA Event-Driven

### Q1. KEDA SQS Scaler 가 사용하는 SQS 메트릭은?

A. ApproximateAgeOfOldestMessage
B. ApproximateNumberOfMessages
C. NumberOfMessagesReceived
D. NumberOfMessagesDeleted

---

### Q2. KEDA Operator 의 IRSA 와 워크로드 Pod 의 IRSA 가 별도인 이유는?

---

### Q3. Kafka scaler 의 `lagThreshold` 가 의미하는 것은?

---

### Q4. partition=3 인 topic 에 maxReplicaCount=10 으로 설정하면?

A. 10 Pod 모두 메시지 받음
B. 3 Pod 만 메시지 받고 나머지는 idle
C. 에러
D. partition 수가 자동 늘어남

---

### Q5. SQS scaler 의 `identityOwner: operator` 와 `pod` 의 차이는?

---

### Q6. KEDA TriggerAuthentication CRD 의 역할은?

---

### Q7. Kafka offsetResetPolicy `latest` vs `earliest` 의 차이는?

---

### Q8. SQS DLQ (Dead Letter Queue) 와 KEDA 의 관계는?

A. KEDA 가 DLQ 도 자동 모니터링
B. KEDA 는 정상 큐만 봄, DLQ 는 사용자가 별도 ScaledObject 로
C. DLQ 의 메시지는 KEDA 가 자동 재처리
D. 무관

---

### Q9. KEDA SQS scaler 가 Pod 0 → 1 로 처음 깨울 때 기다리는 시간은?

---

### Q10. (실습 검증) 현재 클러스터의 모든 KEDA scaler 의 메트릭 현재값을 한 번에 보는 방법은?

---

## 정답

<details>

**Q1**: B
**Q2**: 책임 분리 — Operator 는 큐 길이 모니터링, Pod 는 실제 메시지 처리. IAM 정책 분리로 최소 권한 원칙
**Q3**: 컨슈머 그룹의 lag (가장 최근 produced offset - committed offset). 이 값을 임계로 하여 desired replicas 계산
**Q4**: B — partition 수가 컨슈머의 동시 활성 한계
**Q5**: operator: KEDA Operator Pod 의 IRSA 사용. pod: 워크로드 Pod 의 IRSA 사용
**Q6**: 트리거가 외부 시스템 인증 시 자격증명을 가져올 방법(IRSA, Secret, Vault 등) 정의
**Q7**: latest: 컨슈머 그룹 처음 시작 시 가장 최근 메시지부터. earliest: 토픽의 처음부터
**Q8**: B
**Q9**: pollingInterval 의 1주기 (기본 30초). 0 → 1 은 KEDA 가 즉시 트리거하지만 폴링 간격이 변수
**Q10**: `kubectl get scaledobjects -A -o json | jq '.items[] | {ns:.metadata.namespace, name:.metadata.name, status:.status.health}'`

</details>

다음: [pitfalls.md](./pitfalls.md)
