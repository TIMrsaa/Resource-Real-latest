# Lab 02 — 시식: Prometheus 스크레이프와 OTel Collector 파이프라인

메트릭 행(pull 모델)과 통일 열(Collector의 receivers→processors→exporters)을 최소 구성으로 만집니다.

전제: kind, kubectl, helm.

## Step 1. 클러스터와 관측 대상

```bash
kind create cluster --name observ -q

# /metrics를 노출하는 데모 앱 (Prometheus 형식)
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
  labels: { app: demo }
spec:
  replicas: 1
  selector:
    matchLabels: { app: demo }
  template:
    metadata:
      labels: { app: demo }
    spec:
      containers:
        - name: example-app
          image: quay.io/brancz/prometheus-example-app:v0.3.0
---
apiVersion: v1
kind: Service
metadata:
  name: demo
spec:
  selector: { app: demo }
  ports:
    - port: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: curl
  labels: { run: curl }
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: busybox
      command: ["sh", "-c", "wget -qO- demo:8080/metrics | head -5; sleep 3600"]
EOF
kubectl wait --for=condition=available deploy/demo --timeout=120s
sleep 10 && kubectl logs curl | head -5
```

예상: `http_requests_total{...}` 형식의 텍스트 — **노출 형식이 표준**이라 어떤 수집기든 읽습니다(OpenMetrics가 Prometheus에 흡수된 그 형식).

## Step 2. Prometheus — pull의 실감

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
helm install prom prometheus-community/prometheus -n monitoring --create-namespace \
  --set alertmanager.enabled=false --set prometheus-pushgateway.enabled=false >/dev/null
kubectl -n monitoring rollout status deploy/prom-prometheus-server --timeout=300s

# 데모 앱에 스크레이프 어노테이션 (k8s에서 배운 그 방식)
kubectl patch deployment demo -p '{"spec":{"template":{"metadata":{"annotations":{
  "prometheus.io/scrape":"true","prometheus.io/port":"8080"}}}}}'
sleep 45

# 트래픽 생성 후 PromQL로 질의
kubectl exec curl -- sh -c 'for i in $(seq 1 30); do wget -qO- demo:8080 >/dev/null; done' 2>/dev/null || true
kubectl -n monitoring exec deploy/prom-prometheus-server -c prometheus-server -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total[1m]))' | head -3
```

예상: JSON 응답에 초당 요청률 값. ✅ **pull 모델의 전체 사이클** — 앱은 노출만, Prometheus가 발견(어노테이션)·수집(스크레이프)·저장(TSDB)·질의(PromQL). eks 12의 CloudWatch(push)와 반대 방향임을 체감(심층 11에서 왜 pull인지).

## Step 3. OTel Collector — 통일 열의 실물

```bash
kubectl create namespace otel
kubectl -n otel apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: { name: collector-config }
data:
  config.yaml: |
    receivers:
      otlp:
        protocols: { grpc: { endpoint: 0.0.0.0:4317 } }
    processors:
      batch: {}
    exporters:
      debug: { verbosity: normal }        # 실전: jaeger/prometheus/loki exporter로 교체
    service:
      pipelines:
        traces:  { receivers: [otlp], processors: [batch], exporters: [debug] }
        metrics: { receivers: [otlp], processors: [batch], exporters: [debug] }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: collector }
spec:
  replicas: 1
  selector: { matchLabels: { app: collector } }
  template:
    metadata: { labels: { app: collector } }
    spec:
      containers:
        - name: otelcol
          image: otel/opentelemetry-collector-contrib:latest
          args: ["--config=/etc/otel/config.yaml"]
          ports: [{ containerPort: 4317 }]
          volumeMounts: [{ name: cfg, mountPath: /etc/otel }]
      volumes: [{ name: cfg, configMap: { name: collector-config } }]
---
apiVersion: v1
kind: Service
metadata: { name: collector }
spec:
  selector: { app: collector }
  ports: [{ port: 4317 }]
EOF
kubectl -n otel rollout status deploy/collector --timeout=120s
```

config의 구조가 theory §3 그대로입니다: **receivers → processors → exporters**를 pipelines가 신호별로 조립.

## Step 4. 트레이스 흘려보내기 — telemetrygen

```bash
kubectl -n otel run gen --restart=Never \
  --image=ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  -- traces --otlp-endpoint collector:4317 --otlp-insecure --traces 5
sleep 15
kubectl -n otel logs deploy/collector | grep -E "TracesExporter|ResourceSpans|span" | head -6
```

예상: Collector 로그에 수신한 span들. ✅ **OTLP로 들어와 파이프라인을 지나 exporter로** — 지금은 debug(로그)지만, exporters를 `jaeger:`로 바꾸면 Jaeger로, `prometheusremotewrite:`로 바꾸면 메트릭이 Prometheus로 갑니다. **앱 재계측 없이 백엔드 교체** — Collector가 "관측의 CSI"라는 말의 실체.

## Step 5. 산출물 — 시식 결론

```markdown
# 오늘 만진 것
- 메트릭 행: 노출(/metrics 표준 형식) → 발견(어노테이션) → pull → TSDB → PromQL
- 통일 열: OTLP 수신 → processors → exporters — 백엔드 교체 = exporter 한 줄
- 두 세계의 접점: Collector의 prometheus receiver/exporter — 수렴 진행 중 (theory §4)
- 미룬 질문(심층 예약): TSDB 내부·카디널리티(11), 시맨틱 컨벤션·샘플링(12), 
  트레이스 저장 모델(13), 로그 파이프라인 설계(14)
```

## 정리

```bash
bash cleanup.sh
```
