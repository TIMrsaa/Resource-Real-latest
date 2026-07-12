# 퀴즈 — 19. Prometheus Deep Dive

### Q1. Prometheus 가 pull-based 인 이유 두 가지를 적으세요.

---

### Q2. Cardinality = ?

A. 메트릭 개수
B. 시계열 (label 조합) 개수
C. Pod 개수
D. 라벨 종류 수

---

### Q3. 라벨에 user_id 같은 고유 값을 넣으면 안 되는 이유는?

---

### Q4. ServiceMonitor / PodMonitor 의 차이는?

---

### Q5. Prometheus 의 TSDB chunk 단위는?

A. 1시간
B. 2시간
C. 24시간
D. 가변

---

### Q6. honor_labels 의 효과는?

---

### Q7. /federate 와 remote_write 의 핵심 차이는?

---

### Q8. metricRelabelings 의 흔한 use case 는?

---

### Q9. ServiceMonitor 의 `release: kps` 라벨이 필요한 이유는?

---

### Q10. (실습 검증) 현재 Prometheus 의 시계열 수가 가장 많은 메트릭 5개를 보는 PromQL 은?

---

## 정답

<details>

**Q1**: target 자체 단순 (HTTP 핸들러만), 죽은 target 자동 감지 (`up=0`), Service Discovery 와 통합 용이 (이 중 두 가지)
**Q2**: B
**Q3**: 시계열이 무한 증가 → 메모리/디스크 폭주, 쿼리 느려짐, alert rule evaluation cost 증가
**Q4**: ServiceMonitor 는 K8s Service 의 endpoints 를 scrape, PodMonitor 는 Pod 직접. Service 없는 워크로드면 PodMonitor.
**Q5**: B
**Q6**: 다른 source 의 라벨을 그대로 보존 (덮어쓰지 않음). Federation 시 필수.
**Q7**: /federate 는 pull (중앙 Prom 가 가져옴), remote_write 는 push (edge Prom 가 보냄). 후자가 대규모에 적합.
**Q8**: 불필요한 메트릭 drop, 라벨 정리 (labeldrop, labelreplace), 외부 라벨 추가 등
**Q9**: kube-prometheus-stack 의 Prometheus 가 그 라벨이 있는 ServiceMonitor 만 select (default selector)
**Q10**: `topk(5, count by (__name__)({__name__=~".+"}))`

</details>

다음: [pitfalls.md](./pitfalls.md)
