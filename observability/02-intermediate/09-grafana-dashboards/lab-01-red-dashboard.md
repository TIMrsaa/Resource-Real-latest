# Lab 01 — RED 서비스 대시보드: 변수와 드릴다운

> 08의 스택 위에 RED 대시보드를 변수 기반으로 만들고, 개요→서비스 드릴다운과 배포 마커까지 구현합니다. JSON을 직접 다뤄 lab-02(as code)의 기반을 만듭니다.

## 0. 준비 — 08의 스택 + 두 개의 서비스

```bash
kind create cluster --name grafana
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null; helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=24h

# 서비스 두 개 (payment는 에러 있음, order는 정상) — 변수의 가치를 보이기 위해
kubectl create namespace shop
for svc in payment order; do
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: $svc, namespace: shop }
spec:
  replicas: 2
  selector: { matchLabels: { app: $svc } }
  template:
    metadata: { labels: { app: $svc } }
    spec:
      containers:
        - name: app
          image: quay.io/brancz/prometheus-example-app:v0.5.0
          ports: [{ name: http, containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: $svc, namespace: shop, labels: { app: $svc } }
spec:
  selector: { app: $svc }
  ports: [{ name: metrics, port: 8080 }]
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: { name: $svc, namespace: shop, labels: { release: monitoring } }
spec:
  selector: { matchLabels: { app: $svc } }
  endpoints: [{ port: metrics, interval: 15s }]
EOF
done

# 트래픽: payment는 에러 섞기, order는 정상만
kubectl -n shop run traffic --image=curlimages/curl --restart=Never -- sh -c '
  while true; do
    curl -s http://payment:8080/ >/dev/null; curl -s http://payment:8080/err >/dev/null;
    curl -s http://order:8080/ >/dev/null; curl -s http://order:8080/ >/dev/null;
    sleep 0.3;
  done'
sleep 60
```

## 1. Grafana 접속

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
# 브라우저: http://localhost:3000 (admin / prom-operator — 차트 기본값)
# 내장 대시보드 구경: Dashboards → kube-prometheus-stack의 것들
#   (Node Exporter·Kubernetes 시리즈 — USE 계열의 좋은 예시. 뜯어볼 것)
```

## 2. RED 대시보드를 JSON으로 작성

UI 클릭 대신 JSON을 직접 만듭니다(as code의 사전 연습). 파일로 저장:

```bash
cat > /tmp/red-dashboard.json <<'EOF'
{
  "uid": "svc-red",
  "title": "Service RED",
  "timezone": "browser",
  "templating": { "list": [
    { "name": "namespace", "type": "query", "datasource": "Prometheus",
      "query": "label_values(http_requests_total, namespace)", "refresh": 2 },
    { "name": "service", "type": "query", "datasource": "Prometheus",
      "query": "label_values(http_requests_total{namespace=\"$namespace\"}, service)",
      "refresh": 2, "includeAll": true }
  ]},
  "panels": [
    { "id": 1, "type": "timeseries", "title": "Rate (req/s) — $service",
      "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
      "targets": [{ "expr": "sum by (service) (rate(http_requests_total{namespace=\"$namespace\", service=~\"$service\"}[5m]))" }] },
    { "id": 2, "type": "timeseries", "title": "Error ratio — $service",
      "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0},
      "fieldConfig": { "defaults": { "unit": "percentunit", "thresholds": {
        "steps": [{"color":"green","value":null},{"color":"red","value":0.05}] } } },
      "targets": [{ "expr": "sum by (service) (rate(http_requests_total{namespace=\"$namespace\", service=~\"$service\", code=~\"5..\"}[5m])) / sum by (service) (rate(http_requests_total{namespace=\"$namespace\", service=~\"$service\"}[5m]))" }] },
    { "id": 3, "type": "timeseries", "title": "Duration p50/p95/p99 — $service",
      "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0},
      "targets": [
        { "expr": "histogram_quantile(0.50, sum by (le) (rate(http_request_duration_seconds_bucket{namespace=\"$namespace\", service=~\"$service\"}[5m])))", "legendFormat": "p50" },
        { "expr": "histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace=\"$namespace\", service=~\"$service\"}[5m])))", "legendFormat": "p95" },
        { "expr": "histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{namespace=\"$namespace\", service=~\"$service\"}[5m])))", "legendFormat": "p99" }
      ] }
  ],
  "time": { "from": "now-30m", "to": "now" },
  "schemaVersion": 39
}
EOF
```

UI에서 Dashboards → Import → JSON 붙여넣기로 로드.

**확인 사항:**
- `$namespace`·`$service` 드롭다운이 생겼고, service를 바꾸면 세 패널이 따라 변함 — **대시보드 1개 = 전 서비스**
- payment 선택 → Error ratio가 ~50%(빨간 임계 초과), order → 0% — 같은 화면이 두 상태를 보여줌
- Duration이 p50/p95/p99 세 선(평균 없음 — 03의 규율)
- 참고: 예제 앱의 메트릭에 service 라벨이 없으면 job 라벨로 대체(`service=~"$service"` → `job=~"$service"`) — **자기 데이터의 라벨을 확인하고 쿼리를 맞추는 것**도 훈련의 일부입니다

## 3. 개요(L1) → 서비스(L2) 드릴다운

L1 개요 대시보드를 추가합니다 — 전 서비스 에러율 테이블에서 행을 클릭하면 위의 RED로:

```bash
cat > /tmp/overview-dashboard.json <<'EOF'
{
  "uid": "svc-overview",
  "title": "L1 Overview — All Services",
  "panels": [
    { "id": 1, "type": "table", "title": "Error ratio by service (click → drill down)",
      "gridPos": {"h": 10, "w": 12, "x": 0, "y": 0},
      "targets": [{ "expr": "sort_desc(sum by (service) (rate(http_requests_total{code=~\"5..\"}[5m])) / sum by (service) (rate(http_requests_total[5m])))", "format": "table", "instant": true }],
      "fieldConfig": { "defaults": {
        "links": [{ "title": "Drill down",
          "url": "/d/svc-red/service-red?var-service=${__data.fields.service}" }],
        "unit": "percentunit" } } }
  ],
  "time": { "from": "now-30m", "to": "now" },
  "schemaVersion": 39
}
EOF
# Import 후: 테이블에서 payment 행 클릭 → RED 대시보드가 payment로 열림
```

**핵심** — 링크의 `var-service=${__data.fields.service}`가 **변수를 전달**합니다. 온콜의 동선: L1에서 "빨간 게 뭐야" → 클릭 → L2에서 "언제부터, 얼마나". 클릭 두 번이 질문 두 개를 답합니다.

## 4. 배포 마커 — "언제부터"에 문맥을

```bash
# 배포를 일으킵니다
kubectl -n shop set env deploy/payment DUMMY=v2
kubectl -n shop rollout status deploy/payment

# Grafana annotation으로 배포 시각 기록 (실전: CI/ArgoCD가 API 호출 자동화)
# UI: 대시보드에서 Ctrl+클릭 또는 Annotations 메뉴 → "payment deploy v2" 추가
# API 방식:
curl -s -X POST http://admin:prom-operator@localhost:3000/api/annotations \
  -H "Content-Type: application/json" \
  -d '{"dashboardUID":"svc-red","text":"payment deploy v2","tags":["deploy"]}'
```

그래프에 세로선(마커)이 생깁니다 — **에러율 변화와 배포 시각의 대조**가 한눈에(05의 "그때 무슨 변화가?"를 화면에 내장). 실전에서는 CD 파이프라인(cicd·cncf 16)이 배포마다 이 API를 호출하게 합니다.

## 5. 정리

```bash
kill %1 2>/dev/null || true
kubectl -n shop delete pod traffic --force --grace-period=0 2>/dev/null || true
# 클러스터는 lab-02에서 계속 (JSON 파일도 재사용)
```

## 정리

- RED 3패널(율·에러비율·분위수)이 서비스 대시보드의 뼈대 — recording rule 소비가 이상적
- 변수(연쇄 label_values) = 대시보드 증식 방지 — 새 서비스 자동 반영
- 드릴다운 링크(변수 전달) = 조사 동선의 구현 — L1 클릭이 L2 질문으로
- 배포 마커(annotation API) = "언제부터"에 "무엇이 바뀌어서"를 겹침
- **★ 화면 설계 = 질문 설계 — 패널마다 "이건 어떤 질문의 답인가"가 있어야 합니다**
