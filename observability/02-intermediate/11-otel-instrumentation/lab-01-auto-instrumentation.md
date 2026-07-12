# Lab 01 — 자동 계측: 코드 수정 없이 트레이스 심기

> 계측이 전혀 없는 Python 앱 두 개(A→B 호출)에 OTel Operator의 자동 주입만으로 분산 트레이스를 만들어 냅니다. 04에서 손으로 했던 것(ID 생성·헤더 릴레이)이 전부 자동으로 일어나는 것을 확인합니다.

## 0. 준비

```bash
kind create cluster --name otel

# cert-manager (Operator 웹훅의 전제 — cncf 46의 순서!)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager wait deploy --all --for=condition=Available --timeout=180s

# OTel Operator
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
kubectl -n opentelemetry-operator-system wait deploy --all --for=condition=Available --timeout=180s
```

## 1. 목적지 — 디버그 Collector (받은 span을 로그로)

```bash
kubectl create namespace observability
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata: { name: debug, namespace: observability }
spec:
  mode: deployment
  config:
    receivers:
      otlp: { protocols: { grpc: {}, http: {} } }
    processors:
      batch: {}
    exporters:
      debug: { verbosity: normal }       # 받은 span을 stdout에
    service:
      pipelines:
        traces: { receivers: [otlp], processors: [batch], exporters: [debug] }
EOF
kubectl -n observability rollout status deploy/debug-collector --timeout=120s
```

## 2. Instrumentation CRD — 주입 정의

```bash
kubectl create namespace shop
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata: { name: default, namespace: shop }
spec:
  exporter:
    endpoint: http://debug-collector.observability:4318
  propagators: [tracecontext, baggage]        # ★ W3C traceparent (04)
  sampler: { type: parentbased_traceidratio, argument: "1.0" }  # 실습: 100%
  python:
    env:
      - name: OTEL_EXPORTER_OTLP_PROTOCOL
        value: http/protobuf
EOF
```

## 3. 계측 없는 앱 A→B — 어노테이션만 붙여 배포

```bash
# B: 단순 Flask 서버 (OTel 코드 0줄!)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: app-b-code, namespace: shop }
data:
  app.py: |
    from flask import Flask
    import time
    app = Flask(__name__)
    @app.route("/stock")
    def stock():
        time.sleep(0.15)          # 재고 조회 흉내
        return {"stock": 42}
    app.run(host="0.0.0.0", port=8080)
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-b, namespace: shop }
spec:
  replicas: 1
  selector: { matchLabels: { app: app-b } }
  template:
    metadata:
      labels: { app: app-b }
      annotations:
        instrumentation.opentelemetry.io/inject-python: "true"   # ★ 이 한 줄!
    spec:
      containers:
        - name: app
          image: python:3.12-slim
          command: ["sh","-c","pip install flask requests -q && python /code/app.py"]
          volumeMounts: [{ name: code, mountPath: /code }]
      volumes: [{ name: code, configMap: { name: app-b-code } }]
---
apiVersion: v1
kind: Service
metadata: { name: app-b, namespace: shop }
spec: { selector: { app: app-b }, ports: [{ port: 8080 }] }
EOF

# A: B를 호출하는 서버 (역시 OTel 코드 0줄)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: app-a-code, namespace: shop }
data:
  app.py: |
    from flask import Flask
    import requests
    app = Flask(__name__)
    @app.route("/order")
    def order():
        r = requests.get("http://app-b:8080/stock")   # ← 여기 전파가 자동으로!
        return {"order": "ok", "stock": r.json()["stock"]}
    app.run(host="0.0.0.0", port=8080)
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-a, namespace: shop }
spec:
  replicas: 1
  selector: { matchLabels: { app: app-a } }
  template:
    metadata:
      labels: { app: app-a }
      annotations:
        instrumentation.opentelemetry.io/inject-python: "true"
    spec:
      containers:
        - name: app
          image: python:3.12-slim
          command: ["sh","-c","pip install flask requests -q && python /code/app.py"]
          volumeMounts: [{ name: code, mountPath: /code }]
      volumes: [{ name: code, configMap: { name: app-a-code } }]
---
apiVersion: v1
kind: Service
metadata: { name: app-a, namespace: shop }
spec: { selector: { app: app-a }, ports: [{ port: 8080 }] }
EOF
kubectl -n shop rollout status deploy/app-a deploy/app-b --timeout=300s
```

## 4. 주입의 물증 확인

```bash
# Pod spec이 변형됐습니다 — 웹훅의 손길
kubectl -n shop get pod -l app=app-a -o jsonpath='{.items[0].spec.initContainers[*].name}'
# opentelemetry-auto-instrumentation-python   ← init 컨테이너 주입!
kubectl -n shop get pod -l app=app-a -o jsonpath='{.items[0].spec.containers[0].env[*].name}' | tr ' ' '\n' | grep OTEL | head -5
# OTEL_SERVICE_NAME, OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_PROPAGATORS...
# ← 환경변수 주입 — "마법"의 실체 (theory 2절)
```

## 5. 분산 트레이스 확인 — 04의 수작업이 자동으로

```bash
# 요청 하나
kubectl -n shop run curl --image=curlimages/curl --restart=Never --rm -it -- \
  curl -s http://app-a:8080/order
# {"order":"ok","stock":42}

sleep 10
kubectl -n observability logs deploy/debug-collector | grep -A3 "Name" | head -30
# Span #0  Name: GET /stock   Trace ID: 7f3a...  Parent ID: aa11...  ← B의 서버 span
# Span #1  Name: GET          Trace ID: 7f3a...  Parent ID: bb22...  ← A의 클라이언트 span
# Span #2  Name: GET /order   Trace ID: 7f3a...  Parent ID: (root)  ← A의 서버 span
#          ↑ 전부 같은 Trace ID! — A→B 경계를 traceparent가 자동으로 넘었습니다
```

**대조** — 04 lab-01에서 손으로 했던 모든 것(ID 생성, 헤더 부착, 파싱, parent 연결, 시각 기록)이 코드 0줄로 일어났습니다: Flask 수신 훅이 서버 span을, requests 발신 훅이 클라이언트 span + traceparent 헤더를. **자동 계측 = 경계의 자동화**입니다. B의 `time.sleep(0.15)`가 span duration 150ms로 잡히는 것도 확인하세요 — "어디가 느린가"가 데이터가 됐습니다.

## 6. 자동의 한계 확인 (수동 보강의 자리)

```
지금 트레이스에 없는 것:
  "stock 계산" 내부 단계 (sleep 부분이 왜 걸리는지는 안 보임 — 서버 span 전체뿐)
  비즈니스 속성 (주문 금액·상품 ID)
→ 이것이 수동 계측의 자리: 핵심 경로에 커스텀 span·속성 추가
  (SDK API로 — 자동 80% + 수동 20% 전략)
```

## 7. 정리

```bash
# 클러스터는 lab-02에서 계속
echo "Collector 3패턴·샘플링은 lab-02에서"
```

## 정리

- Operator 주입: Instrumentation CRD + 어노테이션 한 줄 → init 컨테이너·env 주입(물증 확인)
- 코드 0줄로 분산 트레이스: 서버/클라이언트 span + traceparent 자동 릴레이 (04의 수작업 전부)
- 같은 Trace ID로 A→B가 이어짐 — 자동 계측이 "경계"를 공짜로
- 한계: 내부 단계·비즈니스 속성은 수동 보강 (80/20 전략)
- **★ 04의 조직적 벽(전 서비스 협조)이 "어노테이션 한 줄"로 낮아졌습니다 — 마찰 감소가 보급의 열쇠**
