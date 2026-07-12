# Lab 02 — Collector 파이프라인: 강화·샘플링·백엔드 교체

관측의 게이트웨이를 직접 조립합니다 — k8s 메타 부착, tail 샘플링으로 에러만 남기기, 그리고 "앱을 안 건드리고 백엔드 바꾸기".

전제: lab-01의 클러스터(kind: otel), Jaeger·Collector 설치됨.

## Step 1. k8sattributes — 텔레메트리에 Pod 메타 자동 부착

```bash
# RBAC: Collector가 Pod 메타데이터를 읽을 수 있어야 합니다
kubectl -n obs apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: { name: otelcol }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: otelcol }
rules:
  - apiGroups: [""]
    resources: [pods, namespaces, nodes]
    verbs: [get, watch, list]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: otelcol }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: otelcol }
subjects: [{ kind: ServiceAccount, name: otelcol, namespace: obs }]
EOF

kubectl -n obs apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: { name: otelcol-config }
data:
  config.yaml: |
    receivers:
      otlp: { protocols: { grpc: { endpoint: 0.0.0.0:4317 }, http: { endpoint: 0.0.0.0:4318 } } }
    processors:
      memory_limiter: { check_interval: 1s, limit_mib: 256 }
      k8sattributes:                       # ★ Pod 메타를 텔레메트리에 부착
        auth_type: serviceAccount
        extract:
          metadata: [k8s.namespace.name, k8s.pod.name, k8s.deployment.name, k8s.node.name]
      resource:
        attributes:
          - { key: deployment.environment, value: lab, action: upsert }   # 시맨틱 컨벤션 준수
      tail_sampling:                       # ★ 트레이스 완료 후 판단
        decision_wait: 5s
        num_traces: 1000
        policies:
          - name: keep-errors
            type: status_code
            status_code: { status_codes: [ERROR] }
          - name: keep-slow
            type: latency
            latency: { threshold_ms: 300 }
          - name: sample-rest
            type: probabilistic
            probabilistic: { sampling_percentage: 10 }
      batch: {}
    exporters:
      otlp/jaeger: { endpoint: jaeger:4317, tls: { insecure: true } }
      debug: { verbosity: basic }
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, resource, tail_sampling, batch]
          exporters: [otlp/jaeger, debug]
EOF

kubectl -n obs patch deploy otelcol -p '{"spec":{"template":{"spec":{"serviceAccountName":"otelcol"}}}}'
kubectl -n obs rollout restart deploy/otelcol
kubectl -n obs rollout status deploy/otelcol --timeout=180s
```

✅ processors의 **순서**에 주의: `memory_limiter`가 처음(OOM 방어), `batch`가 마지막(전송 효율). 사이에 강화(k8sattributes·resource)와 판단(tail_sampling).

## Step 2. tail 샘플링 검증 — 에러는 남고 정상은 버려집니다

```bash
# 에러를 내는 백엔드 엔드포인트 추가
kubectl -n obs create configmap svc2 --from-literal=gen.py='
import time, random, requests
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.trace import Status, StatusCode

trace.set_tracer_provider(TracerProvider(resource=Resource.create({"service.name": "sampler-demo"})))
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint="otelcol:4317", insecure=True)))
tracer = trace.get_tracer(__name__)

# 정상 90건 (빠름), 에러 5건, 느린 것 5건
for i in range(90):
    with tracer.start_as_current_span("normal") as s:
        s.set_attribute("i", i); time.sleep(0.01)
for i in range(5):
    with tracer.start_as_current_span("error") as s:
        s.set_status(Status(StatusCode.ERROR, "boom")); time.sleep(0.01)
for i in range(5):
    with tracer.start_as_current_span("slow") as s:
        time.sleep(0.4)
print("100 traces sent (90 normal / 5 error / 5 slow)")
' >/dev/null

kubectl -n obs run sampler --rm -i --restart=Never --image=python:3.12-slim \
  --overrides='{"spec":{"volumes":[{"name":"src","configMap":{"name":"svc2"}}],"containers":[{"name":"s","image":"python:3.12-slim","command":["sh","-c","pip install -q opentelemetry-distro opentelemetry-exporter-otlp 2>/dev/null && python /src/gen.py"],"volumeMounts":[{"name":"src","mountPath":"/src"}]}]}}' 2>/dev/null

sleep 20
kubectl -n obs port-forward svc/jaeger 16686:16686 >/dev/null 2>&1 &
sleep 3
curl -s "http://localhost:16686/api/traces?service=sampler-demo&limit=200" | python3 -c "
import json,sys
from collections import Counter
d = json.load(sys.stdin)['data']
names = Counter(t['spans'][0]['operationName'] for t in d)
print(f'저장된 트레이스: {len(d)}건 (보낸 것: 100건)')
for n, c in names.items(): print(f'  {n:8s} {c}건')
print()
print('기대: error 5/5, slow 5/5 (전부 보존), normal은 ~10% 만')
"
```

예상: error·slow는 전부, normal은 일부만. ✅ **tail 샘플링은 결과를 보고 판단**합니다 — head 샘플링이었다면 에러 트레이스도 확률적으로 버려졌을 것(theory §5).

## Step 3. 부착된 메타데이터 확인

```bash
curl -s "http://localhost:16686/api/traces?service=sampler-demo&limit=1" | python3 -c "
import json,sys
t = json.load(sys.stdin)['data'][0]
proc = list(t['processes'].values())[0]
print('Resource 속성 (k8sattributes + resource processor가 붙인 것):')
for tag in proc['tags'][:10]:
    print(f\"  {tag['key']:32s} {tag['value']}\")"
```

예상: `k8s.pod.name`, `k8s.namespace.name`, `deployment.environment=lab` 등. ✅ **앱은 아무것도 안 했는데** Collector가 Pod 컨텍스트를 붙였습니다 — agent 토폴로지가 존재하는 이유이자, 시맨틱 컨벤션 덕에 어느 백엔드에서도 같은 이름으로 조회됩니다.

## Step 4. 백엔드 교체 — OTel의 존재 증명

```bash
# exporter만 바꿔 debug(로그)로 라우팅 — 앱은 재배포하지 않습니다
kubectl -n obs get cm otelcol-config -o jsonpath='{.data.config\.yaml}' | \
  sed 's|exporters: \[otlp/jaeger, debug\]|exporters: [debug]|' > /tmp/cfg.yaml
kubectl -n obs create cm otelcol-config --from-file=config.yaml=/tmp/cfg.yaml \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n obs rollout restart deploy/otelcol && kubectl -n obs rollout status deploy/otelcol --timeout=120s

echo "→ 이제 트레이스는 Jaeger가 아니라 Collector 로그로 갑니다. 앱 코드·배포는 그대로."
echo "  실전에서는 debug 대신 otlp/tempo, otlp/datadog, awsxray 등으로 교체"
echo "  ★ 이것이 OTel의 성공 지표: '백엔드를 바꿀 때 앱을 안 건드렸는가'"
```

## Step 5. 프로덕션 토폴로지 스케치

```bash
cat <<'EOF'
[표준 배포 — theory §4]
  앱(OTLP) → agent (DaemonSet, localhost)
                ├ k8sattributes (Pod 메타)
                └ loadbalancing exporter (routing_key: traceID)  ★ tail 샘플링의 전제
                     ↓
             gateway (Deployment, 풀)
                ├ tail_sampling (한 트레이스의 모든 span이 같은 인스턴스에!)
                ├ 라우팅·필터·재작성
                └ exporters → 트레이스 백엔드 / 메트릭 / 로그

주의: agent에서 tail_sampling을 켜면 안 됩니다 —
      한 트레이스의 span들이 여러 노드에 흩어져 판단이 불가능합니다.
      그래서 loadbalancing exporter로 trace_id 해시 라우팅이 필요합니다.
EOF
```

## Step 6. 산출물

```markdown
# Collector 설계 카드
- processors 순서: memory_limiter(첫) → k8sattributes/resource → tail_sampling → batch(끝)
- 토폴로지: agent(메타 부착·로컬 수집) → gateway(샘플링·라우팅) → 백엔드
- tail 샘플링 정책: 에러 100% / 느린 것 100% / 나머지 N%
- tail의 전제: loadbalancing exporter (routing_key: traceID)
- 백엔드 교체 = exporter 한 줄 (앱 무수정) ← OTel 도입의 성공 지표
- OTel이 안 하는 것: 저장·질의·화면·알람 (06의 격자에서 다른 칸)
```

## 정리

```bash
kill %1 2>/dev/null || true
bash cleanup.sh
```
