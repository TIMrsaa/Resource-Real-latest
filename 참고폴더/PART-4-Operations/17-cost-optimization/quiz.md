# 퀴즈 — 17. Cost Optimization

### Q1. EKS Control Plane 비용은?

A. 인스턴스 별
B. 시간당 약 $0.10/cluster
C. Pod 수 비례
D. 무료

---

### Q2. NAT Gateway 비용 폭증의 가장 흔한 원인은?

A. NAT 자체 시간당 비용
B. ECR pull 트래픽이 NAT 통해 인터넷 → 데이터 전송
C. K8s API 트래픽
D. CloudWatch Logs

---

### Q3. Right-Sizing 의 이상적 utilization 비율은?

---

### Q4. VPA 의 `updateMode: Off` 와 `Auto` 의 차이는?

---

### Q5. HPA + VPA 를 같이 쓸 때 충돌 회피 패턴은?

---

### Q6. OpenCost 가 가격 정보를 어디서 가져오나?

---

### Q7. CloudWatch Logs 비용을 줄이는 방법 두 가지를 적으세요.

---

### Q8. Spot 노드 비용이 갑자기 올라간 경우 점검 1순위는?

---

### Q9. EBS gp3 vs gp2 의 차이는?

A. gp3 가 더 비쌈
B. gp3 가 더 싸고 IOPS/throughput 분리 설정 가능
C. 차이 없음
D. gp3 만 EKS 호환

---

### Q10. (실습 검증) 지난 7일간 가장 비싼 AWS 서비스 3가지를 보는 명령은?

---

## 정답

<details>

**Q1**: B
**Q2**: B
**Q3**: 70~85% 범위 (CPU/Memory 모두). 100% 는 throttling/OOM 위험, 50% 미만은 over-provisioning.
**Q4**: Off 는 추천만 status 에 노출. Auto 는 Pod 를 재시작하며 자동 패치.
**Q5**: VPA 는 Memory 만, HPA 는 CPU. 또는 VPA Off 모드로 사람이 검토.
**Q6**: AWS Pricing API + EKS Spot 가격. Helm chart 의 region 설정 또는 자체 가격 데이터.
**Q7**: 로그 레벨 INFO 이상으로, retention 짧게 (예: 7일), namespace 필터 (Fluent Bit 설정), 큰 로그 GB/일 측정 후 줄이기 (이 중 두 가지)
**Q8**: 인스턴스 타입 (큰 거 자주 launch?) + ondemand fallback 발생? + Karpenter NodePool requirements 검토
**Q9**: B
**Q10**: `aws ce get-cost-and-usage --time-period Start=$(date -u -v-7d +%F),End=$(date -u +%F) --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE --query 'ResultsByTime[].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' --output text | sort -k2 -nr | head -3`

</details>

다음: [pitfalls.md](./pitfalls.md)
