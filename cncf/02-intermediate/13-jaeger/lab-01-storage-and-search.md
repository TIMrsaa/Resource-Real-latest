# Lab 01 — 저장과 검색: 인덱스가 무엇을 가능하게 하는가

Jaeger를 두 백엔드(메모리/Badger, Elasticsearch)로 띄워 검색 능력의 차이를 직접 확인하고, span이 어떻게 조립되는지 API로 봅니다.

전제: kind, kubectl, helm. 메모리 8GB 권장.

## Step 1. 클러스터와 Jaeger(메모리 백엔드)

```bash
kind create cluster --name jaeger -q
kubectl create ns tracing

kubectl -n tracing apply -f - <<'EOF'
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
          env:
            - { name: COLLECTOR_OTLP_ENABLED, value: "true" }
            - { name: SPAN_STORAGE_TYPE, value: "memory" }
            - { name: METRICS_STORAGE_TYPE, value: "prometheus" }
          ports: [{ containerPort: 4317 }, { containerPort: 16686 }]
---
apiVersion: v1
kind: Service
metadata: { name: jaeger }
spec:
  selector: { app: jaeger }
  ports:
    - { name: otlp, port: 4317 }
    - { name: ui, port: 16686 }
EOF
kubectl -n tracing rollout status deploy/jaeger --timeout=180s
kubectl -n tracing port-forward svc/jaeger 16686:16686 >/dev/null 2>&1 &
sleep 3
```

## Step 2. 트레이스 생성기 — 다양한 지연·에러·태그

```bash
kubectl -n tracing create configmap gen --from-literal=gen.py='
import time, random
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.trace import Status, StatusCode

trace.set_tracer_provider(TracerProvider(resource=Resource.create({"service.name": "shop"})))
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint="jaeger:4317", insecure=True)))
t = trace.get_tracer(__name__)

for i in range(60):
    tier = random.choice(["free","gold","gold","free"])
    with t.start_as_current_span("checkout") as root:
        root.set_attribute("myco.user.tier", tier)
        with t.start_as_current_span("db.query") as db:
            db.set_attribute("db.system", "postgresql")
            time.sleep(random.uniform(0.01, 0.03))
        with t.start_as_current_span("payment.call") as pay:
            # gold 사용자 요청 중 일부가 느리고 에러납니다 (조사 대상!)
            if tier == "gold" and i % 7 == 0:
                time.sleep(0.6)
                pay.set_status(Status(StatusCode.ERROR, "gateway timeout"))
                root.set_status(Status(StatusCode.ERROR, "checkout failed"))
            else:
                time.sleep(random.uniform(0.02, 0.05))
print("60 traces sent")
' >/dev/null

kubectl -n tracing run gen --rm -i --restart=Never --image=python:3.12-slim \
  --overrides='{"spec":{"volumes":[{"name":"src","configMap":{"name":"gen"}}],"containers":[{"name":"g","image":"python:3.12-slim","command":["sh","-c","pip install -q opentelemetry-distro opentelemetry-exporter-otlp 2>/dev/null && python /src/gen.py"],"volumeMounts":[{"name":"src","mountPath":"/src"}]}]}}' 2>/dev/null
sleep 10
```

## Step 3. trace_id 정확 조회 — 싼 읽기

```bash
TRACE=$(curl -s "http://localhost:16686/api/traces?service=shop&limit=1" | python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['traceID'])")
echo "trace_id: $TRACE"

curl -s "http://localhost:16686/api/traces/$TRACE" | python3 -c "
import json,sys
t = json.load(sys.stdin)['data'][0]
print(f'span 수: {len(t[\"spans\"])}')
for s in sorted(t['spans'], key=lambda x: x['startTime']):
    dur = s['duration']/1000
    print(f\"  {s['operationName']:16s} {dur:7.1f}ms\")
"
```

✅ **trace_id 조회는 키-값 조회**입니다 — 백엔드가 무엇이든 싸고 빠릅니다. 문제는 다음 단계(trace_id를 모를 때).

## Step 4. 탐색 조회 — 인덱스가 하는 일

```bash
echo "=== ① 에러난 트레이스만 (tag 검색) ==="
curl -s "http://localhost:16686/api/traces?service=shop&tags=%7B%22error%22%3A%22true%22%7D&limit=20" | \
  python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print(f'  {len(d)}건')"

echo "=== ② 500ms 이상 (duration 인덱스) ==="
curl -s "http://localhost:16686/api/traces?service=shop&minDuration=500ms&limit=20" | \
  python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print(f'  {len(d)}건')"

echo "=== ③ 커스텀 태그로 (myco.user.tier=gold) ==="
curl -s "http://localhost:16686/api/traces?service=shop&tags=%7B%22myco.user.tier%22%3A%22gold%22%7D&limit=50" | \
  python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print(f'  {len(d)}건')"
```

예상: 에러 ~8건, 느린 것 ~8건, gold ~30건. ✅ 이 세 검색이 가능한 이유는 **쓰기 시점에 만든 인덱스**(service·duration·tag) 덕입니다(theory §2). 메모리 백엔드는 전부 인덱싱하지만, 프로덕션 규모에서는 이 인덱스가 비용의 대부분이 됩니다.

## Step 5. 백엔드 축 실감 — 무엇을 포기할 수 있나

```bash
cat <<'EOF'
질문: 위 세 검색 중 우리에게 실제로 필요한 것은?

[시나리오 A] 로그에 trace_id가 있고, 메트릭에 exemplar가 있습니다
  → 알람 → exemplar 클릭 → trace_id로 직행 (Step 3의 싼 조회만 필요!)
  → 탐색 인덱스가 거의 불필요 → Tempo류(오브젝트 스토리지 + trace_id 인덱스)로 저비용

[시나리오 B] "느린 요청 찾아줘"를 트레이스 UI에서 합니다
  → duration·tag 인덱스 필요 → Elasticsearch/OpenSearch (운영·비용 무게)

★ 06 지도의 "행 간 연결"(trace_id를 로그·메트릭에 심기)이 
  트레이스 백엔드의 비용을 결정합니다 — 관측 설계가 인프라 비용을 바꾸는 지점
EOF
```

## Step 6. Elasticsearch 백엔드 (선택 — 인덱스의 무게 체감)

```bash
helm repo add elastic https://helm.elastic.co >/dev/null 2>&1
helm install es elastic/elasticsearch -n tracing \
  --set replicas=1 --set minimumMasterNodes=1 \
  --set resources.requests.memory=1Gi --set volumeClaimTemplate.resources.requests.storage=2Gi \
  --set esJavaOpts="-Xmx512m -Xms512m" >/dev/null 2>&1 || echo "(리소스 부족 시 건너뛰어도 됨)"

cat <<'EOF'
ES 백엔드 전환 시 관찰할 것:
  SPAN_STORAGE_TYPE=elasticsearch, ES_SERVER_URLS=http://es-master:9200
  - 인덱스가 날짜별로 생성 (jaeger-span-YYYY-MM-DD)
  - es-index-cleaner 크론잡으로 보존 관리 (트레이스는 짧게! theory §6)
  - 태그 인덱싱 화이트리스트 설정 (--es.tags-as-fields.include) — 카디널리티 방어(11의 교훈)
EOF
```

## Step 7. 산출물

```markdown
# 트레이스 저장 설계 카드
- 읽기 두 종류: trace_id 정확 조회(쌉니다) vs 탐색 조회(인덱스 필요)
- 백엔드 축: trace_id를 어디서 얻는가 → 로그·exemplar면 저비용 저장 가능
- 인덱싱 태그는 화이트리스트 (11의 카디널리티 교훈이 트레이스에도)
- 보존: 7~14일 (장기 추이는 메트릭이 맡습니다)
- 저장량 = span 수 × 크기 × 보존일 — tail 샘플링(12) 후 값으로 산정
```

## 정리

lab-02에서 계속 사용. port-forward 유지.
