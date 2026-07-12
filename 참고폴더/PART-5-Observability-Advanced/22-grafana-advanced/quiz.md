# 퀴즈 — 22. Grafana Advanced

### Q1. Grafana 변수의 `Multi-value` 옵션 + `=~` regex 매칭의 효과는?

---

### Q2. ConfigMap 으로 대시보드를 import 할 때 sidecar 가 watching 하는 라벨은?

---

### Q3. Provisioning vs UI 직접 만들기의 트레이드오프는?

---

### Q4. `label_values(metric, label)` 의 의미는?

---

### Q5. Grafana Alerting 이 Prometheus Alertmanager 보다 좋은 시나리오는?

---

### Q6. ConfigMap 의 1MB 한계를 넘는 큰 대시보드는?

---

### Q7. 변수 cascading ($namespace → $pod) 가 동작하는 메커니즘은?

---

### Q8. 패널의 `Repeat by variable` 의 효과는?

---

### Q9. Grafana 의 `annotations` 는 무엇인가?

---

### Q10. (실습 검증) 새 대시보드의 uid 를 다른 대시보드와 중복으로 만들면?

---

## 정답

<details>

**Q1**: 여러 값 선택 가능 + PromQL 의 라벨 매칭이 OR 로 동작 (`namespace=~"a|b|c"`)
**Q2**: `grafana_dashboard: "1"` (kube-prometheus-stack 의 sidecar 기본 설정)
**Q3**: 코드화 (git, review, 재현성) ↔ 빠른 prototyping. 운영은 provisioning, 탐색은 UI.
**Q4**: 클러스터에서 그 metric 의 그 label 의 unique 값들. 변수 drop-down 에 사용.
**Q5**: 다중 datasource (CloudWatch + Prom + Loki) 통합 alert / Grafana 가 단일 진실 출처
**Q6**: Helm chart 의 `dashboards` values 사용 (gz 압축) 또는 sidecar 의 `extraConfigmapMounts` 로 큰 ConfigMap 분할
**Q7**: 변수 정의 시 다른 변수 reference. Grafana 가 의존성 그래프 평가하여 순서 결정.
**Q8**: 그 변수의 각 값마다 패널을 자동 복제 (예: 각 NS 별 같은 패널)
**Q9**: 시각화 위에 이벤트 마커 (배포 / alert / 사고 시각). Prometheus 쿼리로 동적.
**Q10**: 새 대시보드 import 가 실패 (uid 충돌). 또는 기존 것 덮어씀 (옵션에 따라).

</details>

다음: [pitfalls.md](./pitfalls.md)
