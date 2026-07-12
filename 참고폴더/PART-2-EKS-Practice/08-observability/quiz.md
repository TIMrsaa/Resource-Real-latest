# 퀴즈 — 08. Observability

### Q1. 관측의 3축이 답하는 질문은? (각 축당 1줄)

---

### Q2. CloudWatch Container Insights 가 만드는 4개 Log Group의 차이는?

---

### Q3. ServiceMonitor CRD 는 무엇을 정의하는가?

A. Prometheus 자체 설정
B. Prometheus 가 scrape 할 대상 Service / port / path
C. Service의 health check
D. 알람 규칙

---

### Q4. PromQL `rate(http_requests_total[1m])` 의 의미는?

---

### Q5. Prometheus 의 `retention` 을 늘리면 어떤 트레이드오프?

---

### Q6. Counter / Gauge / Histogram / Summary 차이를 한 줄씩 설명하세요.

---

### Q7. Alertmanager 가 Prometheus 와 분리된 이유는?

---

### Q8. Grafana 의 데이터는 어디서 오는가?

A. Grafana 자체 DB
B. 설정된 Datasource (Prometheus, CloudWatch, Loki 등) 에 매번 쿼리
C. Prometheus 가 push 함
D. 사용자가 직접 입력

---

### Q9. CloudWatch Logs ingestion 비용을 줄이는 방법 두 가지를 적으세요.

---

### Q10. (실습 검증) 현재 클러스터에서 Pod restart 가 가장 많은 Pod 5개를 PromQL로 찾는 쿼리는?

---

## 정답

<details>

**Q1**:
- Metrics: 지금 시스템 상태 (얼마나 바쁜가)
- Logs: 그 순간에 무슨 일이 있었는가
- Traces: 요청이 어떤 경로로 흘렀는가

**Q2**:
- application: 컨테이너 stdout/stderr
- host: 노드 OS 로그
- dataplane: kubelet, container runtime
- performance: 메트릭 (Container Insights 자체)

**Q3**: B
**Q4**: 지난 1분 동안의 평균 RPS (초당 요청)
**Q5**: 더 긴 데이터 보존 ↔ 더 많은 EBS 디스크 사용 + 쿼리 메모리 ↑
**Q6**:
- Counter: 단조 증가만 (재시작 시 0)
- Gauge: 임의로 오르내림 (현재 값)
- Histogram: bucket 별 카운트 (서버 측 quantile 계산용)
- Summary: quantile 직접 계산 (집계 어려움)
**Q7**: 알림 규칙 평가는 Prometheus가, 통지 라우팅/억제/그룹화는 Alertmanager가 — 책임 분리 + 다중 Prometheus 가 같은 Alertmanager 공유 가능
**Q8**: B
**Q9**: 로그 레벨 ↑ (DEBUG 빼기), 파일 단위 필터링 (Fluent Bit 설정), retention 짧게
**Q10**: `topk(5, sum(kube_pod_container_status_restarts_total) by (namespace, pod))`

</details>

다음: [pitfalls.md](./pitfalls.md)
