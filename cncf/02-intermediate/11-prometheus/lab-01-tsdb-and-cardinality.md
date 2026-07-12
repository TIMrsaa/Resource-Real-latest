# Lab 01 — TSDB 저장 구조 관찰과 카디널리티 폭발 재현

Prometheus의 메모리가 무엇으로 차는지 직접 폭발시켜 확인하고, 진단·방어 도구를 손에 넣습니다.

전제: kind, kubectl, helm, python3.

## Step 1. 클러스터와 Prometheus

```bash
kind create cluster --name prom -q
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
helm install prom prometheus-community/prometheus -n mon --create-namespace \
  --set alertmanager.enabled=false \
  --set prometheus-pushgateway.enabled=false \
  --set server.persistentVolume.enabled=false \
  --set server.retention=2h >/dev/null
kubectl -n mon rollout status deploy/prom-prometheus-server --timeout=300s

PROM="kubectl -n mon exec deploy/prom-prometheus-server -c prometheus-server --"
q() { $PROM wget -qO- "http://localhost:9090/api/v1/query?query=$1" | python3 -c "
import json,sys
r=json.load(sys.stdin)['data']['result']
[print(f\"  {x['metric']}  =  {x['value'][1]}\") for x in r[:8]] or print('  (empty)')
"; }
```

## Step 2. TSDB의 현재 상태 — 기준선

```bash
echo "=== head 시계열 수 (지금) ==="
q 'prometheus_tsdb_head_series'
echo "=== head 청크 수 ==="
q 'prometheus_tsdb_head_chunks'
echo "=== 메모리 ==="
q 'process_resident_memory_bytes{job=~".*prometheus.*"}'
```

기준선을 적어두라 — 몇 만 시계열, 수백 MB 정도일 것.

## Step 3. 저장 구조를 눈으로 — WAL과 블록

```bash
$PROM ls -la /data 2>/dev/null | head -8
echo "--- WAL (크래시 복구용 append-only) ---"
$PROM ls /data/wal 2>/dev/null | head -5
echo "--- 블록 (2h마다 head에서 flush) ---"
$PROM ls /data 2>/dev/null | grep -E "^01" | head -3 || echo "(아직 없음 — 2시간 미만)"
```

✅ theory §2의 구조가 디렉터리로: `wal/`(지금 쓰는 중) + `01XXXX/`(영구 블록, 있다면 chunks·index·meta.json).

## Step 4. 카디널리티 폭발 — 나쁜 라벨을 직접 심습니다

```bash
# 요청마다 user_id 라벨을 붙이는 "나쁜 앱"을 흉내 (텍스트 노출)
kubectl -n mon create configmap bad-metrics --from-literal=gen.py='
import http.server, random, time
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type","text/plain"); self.end_headers()
        lines = []
        # 🐛 user_id를 라벨로! 매 스크레이프마다 새 시계열 5000개
        for i in range(5000):
            uid = random.randint(1, 100000)
            lines.append(f'http_requests_total{{path="/api",user_id="{uid}"}} {random.randint(1,100)}')
        self.wfile.write("\n".join(lines).encode()+b"\n")
    def log_message(self,*a): pass
http.server.HTTPServer(("",8080), H).serve_forever()
' >/dev/null

kubectl -n mon apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: bad-app
  annotations: { prometheus.io/scrape: "true", prometheus.io/port: "8080" }
  labels: { app: bad-app }
spec:
  containers:
    - name: app
      image: python:3.12-slim
      command: ["python","/src/gen.py"]
      volumeMounts: [{ name: src, mountPath: /src }]
  volumes: [{ name: src, configMap: { name: bad-metrics } }]
EOF
kubectl -n mon wait --for=condition=ready pod/bad-app --timeout=120s
echo "3분간 스크레이프되게 대기 (매 스크레이프마다 새 user_id 5000개)..."
sleep 180
```

## Step 5. 폭발 확인 — 무엇이 커졌나

```bash
echo "=== head 시계열 수 (폭발 후) ==="
q 'prometheus_tsdb_head_series'
echo "=== 메모리 (폭발 후) ==="
q 'process_resident_memory_bytes{job=~".*prometheus.*"}'

echo "=== 범인 찾기: 메트릭별 시계열 수 top ==="
$PROM wget -qO- 'http://localhost:9090/api/v1/query?query=topk(5,count%20by%20(__name__)({__name__=~%22.%2B%22}))' \
  | python3 -c "
import json,sys
for x in json.load(sys.stdin)['data']['result']:
    print(f\"  {x['metric'].get('__name__','?'):40s} {x['value'][1]:>10s} 시계열\")"
```

예상: `http_requests_total`이 수만 시계열로 1위, head_series와 메모리가 급증. ✅ **샘플이 아니라 시계열이 비쌉니다**(theory §3) — 값은 100 이하의 작은 숫자인데 메모리는 폭발했습니다.

```bash
echo "=== 대상별 샘플 수 (누가 많이 뱉나) ==="
q 'topk(3, scrape_samples_scraped)'
```

## Step 6. 마지막 방어선 — metric_relabel_configs로 저장 전에 버리기

```bash
kubectl -n mon get cm prom-prometheus-server -o jsonpath='{.data.prometheus\.yml}' > /tmp/prom.yml
python3 - <<'EOF'
import re
cfg = open('/tmp/prom.yml').read()
# kubernetes-pods job에 metric_relabel_configs 추가 (user_id 라벨을 가진 메트릭 drop)
patch = """
    metric_relabel_configs:
      - source_labels: [user_id]
        action: drop
        regex: ".+"
"""
cfg = cfg.replace("  - job_name: kubernetes-pods\n", "  - job_name: kubernetes-pods\n" + patch, 1)
open('/tmp/prom-fixed.yml','w').write(cfg)
print("패치 완료 — user_id 라벨이 붙은 샘플은 저장 전에 버린다")
EOF

kubectl -n mon create cm prom-prometheus-server --from-file=prometheus.yml=/tmp/prom-fixed.yml \
  --dry-run=client -o yaml | kubectl -n mon apply -f - >/dev/null
kubectl -n mon rollout restart deploy/prom-prometheus-server
kubectl -n mon rollout status deploy/prom-prometheus-server --timeout=180s
sleep 90

echo "=== 방어 후 head 시계열 수 ==="
PROM="kubectl -n mon exec deploy/prom-prometheus-server -c prometheus-server --"
$PROM wget -qO- 'http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series' | \
  python3 -c "import json,sys; print('  ', json.load(sys.stdin)['data']['result'][0]['value'][1])"
```

예상: 시계열 수가 기준선 근처로 복귀. ✅ **`metric_relabel_configs`는 카디널리티의 최후 방어선** — 앱을 못 고칠 때(서드파티 exporter 등) Prometheus 쪽에서 막습니다. 단 근본 해결은 앱의 라벨 설계입니다.

## Step 7. 오프라인 분석 도구 — promtool

```bash
$PROM promtool tsdb analyze /data 2>/dev/null | head -25 || \
  echo "(블록이 아직 없으면 2시간 후 또는 프로덕션 데이터에서 실행)"
cat <<'EOF'
promtool tsdb analyze 의 출력에서 볼 것:
  - Highest cardinality labels : 어느 라벨이 시계열을 만드는가
  - Highest cardinality metric names : 어느 메트릭이 범인인가
  - Label pairs most involved in churning : 재배포마다 바뀌는 라벨(pod_name 등)
★ 프로덕션 Prometheus에서 분기마다 돌려라 — 카디널리티는 조용히 자랍니다
EOF
```

## Step 8. 산출물

```markdown
# 카디널리티 진단 카드
- 지표: prometheus_tsdb_head_series (추세!), process_resident_memory_bytes
- 범인 찾기: topk(10, count by (__name__)({__name__=~".+"}))
- 대상 찾기: topk(5, scrape_samples_scraped)
- 오프라인: promtool tsdb analyze /data
- 방어: ① 앱의 라벨 설계(근본) ② metric_relabel_configs drop(최후)
- 규칙: 라벨 값은 유한·저카디널리티·시간에 안 늘어남 — user_id는 로그·트레이스로(06)
```

## 정리

lab-02에서 같은 클러스터를 씁니다. 유지.
