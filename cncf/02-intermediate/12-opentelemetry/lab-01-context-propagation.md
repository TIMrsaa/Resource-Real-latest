# Lab 01 — 컨텍스트 전파: 트레이스를 잇고, 끊고, 다시 잇습니다

두 서비스 사이로 traceparent를 흘려보내며 트레이스의 심장을 눈으로 봅니다 — 그리고 06 사고 사례의 "결제 서비스가 트레이스에서 사라진" 상황을 재현합니다.

전제: kind, kubectl, helm.

## Step 1. 클러스터, Jaeger(백엔드), Collector

```bash
kind create cluster --name otel -q

# 백엔드: Jaeger (all-in-one)
kubectl create ns obs
kubectl -n obs apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: jaeger }
spec:
  replicas: 1
  selector: { matchLabels: { app: jaeger } }
  template:
    metadata: { labels: { app: jaeger } }
    spec:
      containers:
        - name: jaeger
          image: jaegertracing/all-in-one:1.60
          env: [{ name: COLLECTOR_OTLP_ENABLED, value: "true" }]
          ports: [{ containerPort: 4317 }, { containerPort: 16686 }]
---
apiVersion: v1
kind: Service
metadata: { name: jaeger }
spec:
  selector: { app: jaeger }
  ports:
    - { name: otlp, port: 4317 }
    - { name: ui,   port: 16686 }
EOF
kubectl -n obs rollout status deploy/jaeger --timeout=180s
```

## Step 2. Collector (agent 역할)

```bash
kubectl -n obs apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: { name: otelcol-config }
data:
  config.yaml: |
    receivers:
      otlp: { protocols: { grpc: { endpoint: 0.0.0.0:4317 }, http: { endpoint: 0.0.0.0:4318 } } }
    processors:
      memory_limiter: { check_interval: 1s, limit_mib: 256 }   # 항상 첫 번째
      batch: {}                                                 # 항상 마지막
    exporters:
      otlp/jaeger: { endpoint: jaeger:4317, tls: { insecure: true } }
      debug: { verbosity: basic }
    service:
      pipelines:
        traces: { receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlp/jaeger, debug] }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: otelcol }
spec:
  replicas: 1
  selector: { matchLabels: { app: otelcol } }
  template:
    metadata: { labels: { app: otelcol } }
    spec:
      containers:
        - name: col
          image: otel/opentelemetry-collector-contrib:latest
          args: ["--config=/etc/otel/config.yaml"]
          volumeMounts: [{ name: cfg, mountPath: /etc/otel }]
      volumes: [{ name: cfg, configMap: { name: otelcol-config } }]
---
apiVersion: v1
kind: Service
metadata: { name: otelcol }
spec:
  selector: { app: otelcol }
  ports: [{ name: grpc, port: 4317 }, { name: http, port: 4318 }]
EOF
kubectl -n obs rollout status deploy/otelcol --timeout=180s
```

## Step 3. 두 서비스 — 전파가 되는 버전

```bash
kubectl -n obs create configmap svc-code --from-literal=frontend.py='
import os, requests
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.requests import RequestsInstrumentor

trace.set_tracer_provider(TracerProvider(resource=Resource.create({"service.name": "frontend"})))
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint="otelcol:4317", insecure=True)))
RequestsInstrumentor().instrument()          # ★ 자동 계측: traceparent를 자동 inject
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("checkout") as span:
    span.set_attribute("myco.order.tier", "gold")     # 커스텀은 자기 네임스페이스로
    r = requests.get("http://backend:8000/pay", timeout=5)
    print("frontend ->", r.text)
' --from-literal=backend.py='
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from flask import Flask
import time

trace.set_tracer_provider(TracerProvider(resource=Resource.create({"service.name": "backend"})))
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint="otelcol:4317", insecure=True)))
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)      # ★ 자동 계측: traceparent를 자동 extract
@app.route("/pay")
def pay():
    time.sleep(0.2)
    return "paid"
app.run(host="0.0.0.0", port=8000)
' >/dev/null

kubectl -n obs apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: backend }
spec:
  replicas: 1
  selector: { matchLabels: { app: backend } }
  template:
    metadata: { labels: { app: backend } }
    spec:
      containers:
        - name: app
          image: python:3.12-slim
          command: ["sh","-c","pip install -q flask requests opentelemetry-distro opentelemetry-exporter-otlp opentelemetry-instrumentation-flask opentelemetry-instrumentation-requests 2>/dev/null && python /src/backend.py"]
          volumeMounts: [{ name: src, mountPath: /src }]
      volumes: [{ name: src, configMap: { name: svc-code } }]
---
apiVersion: v1
kind: Service
metadata: { name: backend }
spec:
  selector: { app: backend }
  ports: [{ port: 8000 }]
EOF
kubectl -n obs rollout status deploy/backend --timeout=300s
```

## Step 4. 트레이스 생성 — 두 span이 하나로 이어집니다

```bash
kubectl -n obs run caller --rm -i --restart=Never --image=python:3.12-slim \
  --overrides='{"spec":{"volumes":[{"name":"src","configMap":{"name":"svc-code"}}],"containers":[{"name":"caller","image":"python:3.12-slim","command":["sh","-c","pip install -q requests opentelemetry-distro opentelemetry-exporter-otlp opentelemetry-instrumentation-requests 2>/dev/null && python /src/frontend.py"],"volumeMounts":[{"name":"src","mountPath":"/src"}]}]}}' 2>/dev/null

sleep 10
kubectl -n obs logs deploy/otelcol --tail=30 | grep -iE "spans|trace" | head -5
```

Jaeger UI로 확인:

```bash
kubectl -n obs port-forward svc/jaeger 16686:16686 >/dev/null 2>&1 &
sleep 3
curl -s "http://localhost:16686/api/traces?service=frontend&limit=1" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']
if not d: print('트레이스 없음 (조금 더 기다려보세요)'); raise SystemExit
t = d[0]
print(f\"trace_id: {t['traceID']}\")
print(f\"span 수: {len(t['spans'])}\")
for s in t['spans']:
    proc = t['processes'][s['processID']]['serviceName']
    parent = [r['spanID'] for r in s.get('references',[]) if r['refType']=='CHILD_OF']
    print(f\"  {proc:10s} {s['operationName']:20s} parent={parent or '(root)'}\")
"
```

예상: **span 2개, 같은 trace_id**, backend의 span이 frontend의 자식. ✅ traceparent 헤더가 HTTP 요청에 실려 갔고(inject), Flask 계측이 그것을 복원했습니다(extract) — theory §2의 흐름 그대로.

## Step 5. 전파 끊기 — 06 사고 사례 재현

```bash
# 계측 안 된 HTTP 클라이언트로 호출 (RequestsInstrumentor 없이 — 헤더를 안 붙입니다)
kubectl -n obs create configmap broken --from-literal=broken.py='
import requests, urllib.request
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

trace.set_tracer_provider(TracerProvider(resource=Resource.create({"service.name": "frontend-broken"})))
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint="otelcol:4317", insecure=True)))
tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("checkout-broken"):
    # 🐛 계측되지 않은 클라이언트 — traceparent 헤더가 안 붙습니다
    urllib.request.urlopen("http://backend:8000/pay", timeout=5).read()
    print("done (컨텍스트 전파 안 됨)")
' >/dev/null

kubectl -n obs run broken --rm -i --restart=Never --image=python:3.12-slim \
  --overrides='{"spec":{"volumes":[{"name":"src","configMap":{"name":"broken"}}],"containers":[{"name":"broken","image":"python:3.12-slim","command":["sh","-c","pip install -q opentelemetry-distro opentelemetry-exporter-otlp 2>/dev/null && python /src/broken.py"],"volumeMounts":[{"name":"src","mountPath":"/src"}]}]}}' 2>/dev/null

sleep 10
curl -s "http://localhost:16686/api/traces?service=frontend-broken&limit=1" | python3 -c "
import json,sys
t = json.load(sys.stdin)['data'][0]
print(f\"frontend-broken 트레이스의 span 수: {len(t['spans'])}  ← 1이면 끊긴 것\")"
curl -s "http://localhost:16686/api/traces?service=backend&limit=2" | python3 -c "
import json,sys
for t in json.load(sys.stdin)['data'][:2]:
    print(f\"backend 트레이스 {t['traceID'][:12]}... span={len(t['spans'])}  (루트가 backend면 고아 트레이스)\")"
```

예상: frontend-broken은 span 1개, backend는 **별도의 새 트레이스**(고아). ✅ 이것이 06 사고 사례의 "결제 서비스에서 트레이스가 끊긴" 상황 — 헤더 하나가 빠지면 여정이 두 조각이 납니다.

## Step 6. 진단 카드

```markdown
# 전파 끊김 진단 (theory §2)
증상: 조각난 트레이스(루트가 여러 개), 특정 서비스만 트레이스에 안 보임, span 수가 항상 1
원인 4대:
  ① 비동기 큐(Kafka/SQS) — 메시지 헤더에 traceparent를 실었는가요? (수동 inject 필요)
  ② 스레드/코루틴 경계 — 컨텍스트가 thread-local, 워커로 안 넘어감
  ③ 수동 HTTP 클라이언트 — 계측 라이브러리를 안 거침 (Step 5)
  ④ 미계측 서비스 — 중간 서비스가 헤더를 버림 (프록시·게이트웨이 포함!)
확인: 요청 헤더에 traceparent가 실제로 있는가 (tcpdump·로그·미들웨어)
```

## 정리

lab-02에서 같은 클러스터 사용. port-forward는 종료:

```bash
kill %1 2>/dev/null || true
```
