# 퀴즈 — 12. KEDA Basics

### Q1. KEDA 가 HPA 보다 잘하는 것 두 가지를 적으세요.

---

### Q2. ScaledObject 가 만드는 K8s 리소스는?

A. Deployment
B. HPA (자동)
C. CronJob
D. Pod

---

### Q3. Scale-to-zero 가 가능한 이유는?

---

### Q4. KEDA 의 폴링 주기는 어디서 설정?

A. Helm values
B. ScaledObject 의 `pollingInterval`
C. HPA 의 spec
D. Cluster-wide 고정

---

### Q5. ScaledJob 과 ScaledObject 의 차이를 한 줄로?

---

### Q6. 여러 trigger 가 있을 때 결합 로직은?

A. AND (모두 임계 넘어야 scale up)
B. OR (어느 하나라도)
C. 가장 큰 값
D. 평균

---

### Q7. `cooldownPeriod: 300` 의 의미는?

---

### Q8. Cron trigger 의 `start: "0 9 * * mon-fri", end: "0 18 * * mon-fri"` 가 의미하는 것은?

---

### Q9. KEDA Operator 가 죽으면 (몇 분간) 어떤 일이 벌어지나?

---

### Q10. (실습 검증) 현재 클러스터의 모든 ScaledObject 를 한 번에 보고, 각각이 만든 HPA 도 함께 보는 명령은?

---

## 정답

<details>

**Q1**: scale-to-zero, 다양한 외부 이벤트 트리거 (큐, DB, Prometheus 등)
**Q2**: B
**Q3**: KEDA Operator 가 직접 Deployment.spec.replicas 를 0 으로 패치 (HPA 는 minReplicas: 1 한계 우회)
**Q4**: B
**Q5**: ScaledObject 는 Deployment 를 N replicas 로. ScaledJob 은 큐 메시지 N 개 → Job N 개 (단발성)
**Q6**: B (OR)
**Q7**: 모든 trigger 가 임계 미만으로 떨어진 뒤 300초 동안 유지되면 scale down
**Q8**: 평일 09:00~18:00 동안 desiredReplicas 만큼 보장
**Q9**: 메트릭 폴링 멈추니 scale 변화 정지. 기존 Pod 수는 유지. 다른 부분(스케줄링/실행)에는 영향 없음. 복구되면 다시 동작.
**Q10**: `kubectl get scaledobjects.keda.sh,hpa -A`

</details>

다음: [pitfalls.md](./pitfalls.md)
