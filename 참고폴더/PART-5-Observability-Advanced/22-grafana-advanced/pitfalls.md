# 흔한 함정 5선 — 22. Grafana Advanced

## 1. ConfigMap 라벨 누락으로 sidecar 가 import 안 함

**증상**: ConfigMap 만들었는데 Grafana 에 대시보드 안 보임.

**원인**: `grafana_dashboard: "1"` 라벨 없음.

**해결**:
```bash
kubectl label cm <name> -n monitoring grafana_dashboard=1
```

또는 sidecar 가 watching 하는 라벨 키 확인:
```bash
kubectl get deploy kps-grafana -n monitoring -o yaml | yq '.spec.template.spec.containers[] | select(.name == "grafana-sc-dashboard") | .env'
```

`LABEL`, `LABEL_VALUE` 환경변수가 그 키/값.

---

## 2. 대시보드 JSON 의 datasource UID 가 환경마다 다름

**증상**: 다른 클러스터에 import 하니 panel 들이 "Datasource not found".

**원인**: dashboard JSON 안에 datasource UID (랜덤 문자열) 가 hardcoded.

**해결**:
```json
"targets": [{
  "datasource": {"type": "prometheus", "uid": "${DS_PROMETHEUS}"},
  "expr": "..."
}]
```

`${DS_PROMETHEUS}` 형태로 변수화. import 시 사용자가 선택. 또는 datasource name 으로 reference (UID 대신).

---

## 3. 변수의 query 가 비싸 대시보드 로딩 느림

**증상**: 대시보드 처음 열 때 5+초 대기.

**원인**: 변수 query 가 큰 메트릭 전체 카디널리티 평가 (예: `label_values(container_cpu_usage_seconds_total, pod)` — 모든 Pod).

**해결**:
- 더 작은 메트릭 사용 (`label_values(kube_pod_info, pod)`)
- 변수 cascading 으로 점진 좁힘
- TTL 캐시 활용 (Grafana 가 변수 결과 캐시)

---

## 4. Alert 가 Firing 인데 통지 안 옴

**원인 후보**:
- Notification policy 의 matchers 가 alert 의 labels 와 안 맞음
- Contact point 의 webhook URL 잘못
- Grafana 의 Alertmanager 가 Pause 됨

**진단**:
- Alerting → Alert rules → 그 규칙의 history
- Alerting → Notification policies → 어디로 라우팅?
- Contact points 의 Test 버튼

---

## 5. 대시보드의 변수 값이 영속 안 됨 (URL 새로고침 시 초기화)

**원인**: Variables 의 `Refresh` 설정이 `On Dashboard Load`. URL parameter 가 변수 값을 덮어씀.

**해결**: 각 변수의 Selection options:
- `Multi-value` ✓
- `Include All option` ✓
- 기본 값 설정

URL 에 `?var-namespace=order&var-service=order-service` 형태로 영속.

대시보드 URL 공유 시 자동으로 현재 변수 값 포함됨.
