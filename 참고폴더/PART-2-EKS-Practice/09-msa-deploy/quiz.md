# 퀴즈 — 09. MSA 배포

### Q1. 본 lab 에서 notification-service 가 의도적으로 CrashLoop 인 이유는?

---

### Q2. order-service 가 user-service 를 gRPC로 호출할 때 DNS 이름은?

A. `user-service.svc.cluster.local`
B. `user-service.order`
C. `user-service:50051`
D. 모두 가능 (같은 NS면 짧게도 OK)

---

### Q3. ALB 가 같은 그룹의 여러 Ingress 를 공유하게 하는 어노테이션은?

---

### Q4. Headless Service (`clusterIP: None`) 를 payment/notification 에 쓴 이유는?

---

### Q5. ECR 의 이미지를 Pod이 pull 하지 못할 때 점검 1순위는?

A. ImagePullSecret 누락
B. 노드 IAM Role 의 ECR ReadOnly 정책
C. 이미지 태그 오타
D. ECR 리포지토리 정책

---

### Q6. ServiceMonitor 의 `namespaceSelector` 가 다른 NS 를 가리킬 수 있는 이유는?

---

### Q7. Prometheus 가 `up{namespace="order"}` 에서 어떤 정보를 알 수 있는가?

A. Pod이 Ready 인지
B. metrics endpoint 가 scrape 가능한지
C. Pod의 CPU 사용률
D. 컨테이너 재시작 횟수

---

### Q8. ALB Ingress 가 frontend 와 order-service 양쪽으로 라우팅하는 매니페스트 구조는?

A. 두 Ingress 리소스 + group.name 어노테이션
B. 단일 Ingress 리소스 + 두 paths
C. 둘 다 가능
D. 단일 Ingress + 두 Service 가 자동 결합

---

### Q9. 본 lab 의 5개 Service 중 외부로 노출되는 것은?

A. 모두
B. frontend 만
C. frontend + order-service (Ingress)
D. 모두 ClusterIP라 외부 노출 없음

---

### Q10. (실습 검증) `order` NS 의 모든 Pod 의 메트릭 endpoint 가 200 응답하는지 한 번에 확인하는 명령은?

---

## 정답

<details>

**Q1**: Kafka 가 클러스터 안에 없어 KAFKA_BROKERS 연결 실패 → CrashLoop. Part 3 에서 Kafka 를 띄우면 정상 동작.
**Q2**: D
**Q3**: `alb.ingress.kubernetes.io/group.name`
**Q4**: ClusterIP 가 필요 없음 (외부 호출자 없음). 메트릭만 노출하면 충분 + Service 자체는 ServiceMonitor 가 selector 매칭하기 위해 필요
**Q5**: B (lab-01 에서 점검)
**Q6**: ServiceMonitor 가 cluster-scoped 가 아니라 RBAC + Prometheus Operator 의 권한이 cluster 전체에 미침
**Q7**: B
**Q8**: C
**Q9**: C
**Q10**: `for p in $(kubectl get pods -n order -o name); do echo -n "$p: "; kubectl exec -n order $p --container app -- wget -qO- localhost:9090/healthz -S 2>&1 | grep HTTP || echo "fail"; done`

</details>

다음: [pitfalls.md](./pitfalls.md)
