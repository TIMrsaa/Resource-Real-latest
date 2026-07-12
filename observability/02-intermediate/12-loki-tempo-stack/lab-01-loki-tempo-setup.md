# Lab 01 — Loki·Tempo 배포와 파이프라인 연결

> 그동안 stdout·debug로 흉내 내던 목적지를 실물로 바꿉니다 — Fluent Bit→Loki, OTel gateway→Tempo. 그리고 LogQL로 첫 검색을 합니다.

## 0. 준비 — 통합 스택 구축

```bash
kind create cluster --name correlate

# ① kube-prometheus-stack (Grafana 포함 — exemplar 기능 켜기)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.enableFeatures={exemplar-storage} \
  --set prometheus.prometheusSpec.retention=24h

# ② Loki (단일 바이너리 모드 — 학습용)
helm install loki grafana/loki -n monitoring \
  --set deploymentMode=SingleBinary \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem \
  --set loki.auth_enabled=false \
  --set singleBinary.replicas=1 \
  --set loki.useTestSchema=true

# ③ Tempo (단일 바이너리)
helm install tempo grafana/tempo -n monitoring
kubectl -n monitoring get pods | grep -E "loki|tempo"
# loki-0, tempo-0 Running
```

## 1. 로그 파이프라인 연결 — Fluent Bit → Loki

```bash
helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null; helm repo update
cat > /tmp/fb-loki.yaml <<'EOF'
config:
  service: |
    [SERVICE]
        Flush         1
        HTTP_Server   On
        HTTP_Port     2020
        storage.path  /var/log/flb-storage/
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Tag               kube.*
        multiline.parser  cri
        DB                /var/log/flb_kube.db
        storage.type      filesystem
  filters: |
    [FILTER]
        Name              kubernetes
        Match             kube.*
        Merge_Log         On
        Keep_Log          Off
  outputs: |
    [OUTPUT]
        Name              loki
        Match             kube.*
        Host              loki.monitoring.svc.cluster.local
        Port              3100
        # ★ 라벨 선별 — 소수만 승격 (theory 1절의 규율)
        labels            job=fluent-bit, namespace=$kubernetes['namespace_name'], app=$kubernetes['labels']['app']
        auto_kubernetes_labels off
        storage.total_limit_size 200M
EOF
helm install fluent-bit fluent/fluent-bit -n monitoring -f /tmp/fb-loki.yaml
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s
```

**설정 주목** — `labels`에 namespace·app만 승격했습니다. trace_id·pod명 전부를 라벨로 하면 스트림 폭발(03의 물리가 Loki에) — 나머지는 본문(JSON)에 남아 `| json`으로 꺼냅니다.

## 2. 트레이스 파이프라인 연결 — OTel gateway → Tempo

11의 구조를 재구축하되 exporter만 Tempo로:

```bash
# cert-manager + OTel Operator (11과 동일)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager wait deploy --all --for=condition=Available --timeout=180s
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
kubectl -n opentelemetry-operator-system wait deploy --all --for=condition=Available --timeout=180s

kubectl create namespace observability
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata: { name: gateway, namespace: observability }
spec:
  mode: deployment
  config:
    receivers:
      otlp: { protocols: { grpc: {}, http: {} } }
    processors:
      memory_limiter: { check_interval: 1s, limit_percentage: 75, spike_limit_percentage: 20 }
      k8sattributes: {}
      batch: {}
    exporters:
      otlp/tempo:
        endpoint: tempo.monitoring.svc.cluster.local:4317   # ★ debug → Tempo!
        tls: { insecure: true }
    service:
      pipelines:
        traces: { receivers: [otlp], processors: [memory_limiter, k8sattributes, batch], exporters: [otlp/tempo] }
EOF
kubectl -n observability rollout status deploy/gateway-collector --timeout=120s
```

**11의 보상 확인** — 백엔드 교체가 exporter 한 줄이었습니다. 앱·계측·agent는 아무것도 몰라도 됩니다 — Collector가 완충재라는 설계(11)의 실증.

## 3. trace_id를 로그에 남기는 앱 (02+04 규약의 실전판)

```bash
kubectl create namespace shop
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata: { name: default, namespace: shop }
spec:
  exporter: { endpoint: http://gateway-collector.observability:4318 }
  propagators: [tracecontext]
  sampler: { type: parentbased_traceidratio, argument: "1.0" }
  python:
    env: [{ name: OTEL_EXPORTER_OTLP_PROTOCOL, value: http/protobuf }]
---
apiVersion: v1
kind: ConfigMap
metadata: { name: app-code, namespace: shop }
data:
  app.py: |
    from flask import Flask
    from opentelemetry import trace
    import json, time, random, sys
    app = Flask(__name__)
    def log(level, event, **kw):
        ctx = trace.get_current_span().get_span_context()
        rec = {"level": level, "event": event,
               "trace_id": format(ctx.trace_id, "032x"),   # ★ 02의 규약!
               **kw}
        print(json.dumps(rec)); sys.stdout.flush()
    @app.route("/pay")
    def pay():
        if random.random() < 0.3:
            time.sleep(1.2)                     # 느린 경로 (PG timeout 흉내)
            log("error", "pg_timeout", retries=3)
            return {"status": "fail"}, 502
        time.sleep(0.05)
        log("info", "payment_ok")
        return {"status": "ok"}
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: payment, namespace: shop }
spec:
  replicas: 1
  selector: { matchLabels: { app: payment } }
  template:
    metadata:
      labels: { app: payment }
      annotations: { instrumentation.opentelemetry.io/inject-python: "true" }
    spec:
      containers:
        - name: app
          image: python:3.12-slim
          command: ["sh","-c","pip install flask -q && flask --app /code/app.py run --host=0.0.0.0 --port=8080"]
          volumeMounts: [{ name: code, mountPath: /code }]
      volumes: [{ name: code, configMap: { name: app-code } }]
---
apiVersion: v1
kind: Service
metadata: { name: payment, namespace: shop }
spec: { selector: { app: payment }, ports: [{ port: 8080 }] }
EOF
kubectl -n shop rollout status deploy/payment --timeout=300s

# 트래픽
kubectl -n shop run traffic --image=curlimages/curl --restart=Never -- sh -c '
  while true; do curl -s http://payment:8080/pay >/dev/null; sleep 0.5; done'
sleep 60
```

## 4. 첫 LogQL — 라벨로 좁히고 본문에서 꺼내기

```bash
kubectl -n monitoring port-forward svc/loki 3100:3100 &
sleep 2
# 라벨 확인
curl -s 'localhost:3100/loki/api/v1/labels' | head -c 200
# ["app","job","namespace"...]  ← 승격한 소수 라벨만!

# LogQL: 라벨로 좁힘 + JSON 파싱 + 필드 필터
curl -s -G 'localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="shop", app="payment"} | json | event="pg_timeout"' \
  --data-urlencode 'limit=2' | grep -o '"trace_id":"[a-f0-9]*"' | head -2
# "trace_id":"7f3a..."  ← ★ 에러 로그에서 trace_id가 나옵니다 — 상관의 재료!
kill %1
```

## 5. 정리

```bash
# 클러스터는 lab-02(상관·캡스톤)에서 계속
echo "상관 배선은 lab-02에서"
```

## 정리

- 목적지 실물화: Fluent Bit→Loki(라벨 소수 승격), gateway→Tempo(exporter 한 줄 — 11의 보상)
- Loki 라벨 규율 실천: namespace·app만 — trace_id는 본문에 (스트림 폭발 방지)
- 앱이 trace_id를 JSON 로그에 남김 — 02(구조화)+04(전파)의 규약이 합류
- LogQL 2단: {라벨} 좁힘 → | json 필드 추출·필터
- **★ 에러 로그에서 trace_id가 나왔습니다 — 다음 랩에서 이 실로 신호들을 잇습니다**
