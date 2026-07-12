# 퀴즈 — 14. Karpenter + KEDA Combo

### Q1. KEDA + Karpenter 조합이 가장 효과적인 트래픽 패턴은?

A. 24시간 일정한 트래픽
B. burst (간헐적 폭증)
C. 매우 낮은 트래픽
D. 위 모두

---

### Q2. 이 시나리오에서 Pod 가 Pending 상태에 머무는 이유는?

A. KEDA 가 잘못 동작
B. 기존 노드 자원 부족 — Karpenter 가 새 노드 만들기 전까지
C. ECR pull 지연
D. PDB 막음

---

### Q3. Karpenter 가 노드 인스턴스 타입을 어떻게 결정?

---

### Q4. 다음 시퀀스에서 어디가 가장 시간이 많이 걸리나? 보통?

```
메시지 도착 → KEDA 폴링 → Pod replicas 증가 → 노드 부족 감지 → NodeClaim → EC2 launch → 노드 join → Pod 스케줄
```

---

### Q5. cold start 를 줄이는 방법 두 가지를 적으세요.

---

### Q6. maxReplicaCount 를 1000 으로 늘리면 처리 더 빠를까?

A. 무조건 빠름
B. partition / IP / 노드 자원 한계로 결국 같음
C. 느려짐
D. KEDA 가 자동 조정

---

### Q7. 큐 처리 끝난 직후 Pod 0 으로 안 줄어드는 이유는?

---

### Q8. 시나리오 끝난 후 EC2 노드가 영영 안 회수되는 케이스는?

A. cleanup 안 함
B. PDB 가 너무 빡빡
C. KEDA 가 Pod 를 안 줄임 (큐 lag stuck)
D. 위 모두 가능

---

### Q9. 같은 시나리오를 항상 30 Pod 켜둔 상태와 비교 시 비용 절감 비율은?

---

### Q10. (실습 검증) Karpenter 가 1시간 안에 만들고 종료한 EC2 인스턴스의 사용 시간을 합산하는 명령은?

---

## 정답

<details>

**Q1**: B
**Q2**: B
**Q3**: Pending Pod 의 합산 requests + 호환 가능한 instance family 中 Spot 가격 / 가용성 우선
**Q4**: 보통 NodeClaim → EC2 launch + 노드 join 단계 (1~1.5분). KEDA 폴링은 15~30초.
**Q5**: minReplicaCount 를 1 이상으로 (일부 capacity 유지), 이미지 distroless/scratch 로 작게, 노드 워밍 (idle Pod), Pod startupProbe 최적화 (이 중 두 가지)
**Q6**: B — partition/노드 자원/IP 한계가 결국 병목
**Q7**: KEDA 의 cooldownPeriod (기본 5분, 본 lab 90초). 일시적 트래픽 변동에 너무 민감하게 줄이지 않으려는 안전장치
**Q8**: D
**Q9**: 90~95% (peak 시간만 비용 발생 vs 항상 켜둠)
**Q10**: `aws ec2 describe-instances --filters Name=tag:karpenter.sh/nodepool,Values=spot --query 'Reservations[].Instances[].[InstanceId,LaunchTime,StateTransitionReason]' --output text` 의 결과를 파싱하거나, CloudTrail RunInstances/TerminateInstances 이벤트 추적

</details>

다음: [pitfalls.md](./pitfalls.md)
