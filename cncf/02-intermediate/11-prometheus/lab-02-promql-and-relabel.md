# Lab 02 — PromQL의 함정 실측과 서비스 디스커버리·relabeling

`rate()`가 왜 사람의 직관과 다른지 숫자로 확인하고, Prometheus의 진짜 확장 지점(relabeling)을 만집니다.

전제: lab-01의 클러스터(kind: prom).

## Step 1. 예측 가능한 카운터 앱

```bash
kubectl -n mon delete pod bad-app --ignore-not-found >/dev/null
kubectl -n mon create configmap counter-app --from-literal=app.py='
import http.server, threading, time
counter = 0
def tick():
    global counter
    while True:
        counter += 10          # 정확히 초당 10 증가
        time.sleep(1)
threading.Thread(target=tick, daemon=True).start()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type","text/plain"); self.end_headers()
        self.wfile.write(f"requests_total {counter}\n".encode())
    def log_message(self,*a): pass
http.server.HTTPServer(("",8080), H).serve_forever()
' --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n mon apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: counter
  annotations: { prometheus.io/scrape: "true", prometheus.io/port: "8080" }
  labels: { app: counter }
spec:
  containers:
    - name: app
      image: python:3.12-slim
      command: ["python","/src/app.py"]
      volumeMounts: [{ name: src, mountPath: /src }]
  volumes: [{ name: src, configMap: { name: counter-app } }]
EOF
kubectl -n mon wait --for=condition=ready pod/counter --timeout=120s
echo "5분 대기 (rate 창을 채우기 위해)..."; sleep 300
```

## Step 2. rate()의 진실 — 정답은 10인데?

```bash
PROM="kubectl -n mon exec deploy/prom-prometheus-server -c prometheus-server --"
qv() { $PROM wget -qO- "http://localhost:9090/api/v1/query?query=$1" | \
  python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; print(f'  {r[0][\"value\"][1] if r else \"(empty)\"}')" ; }

echo "실제 증가율: 초당 정확히 10"
echo "rate[1m]  →"; qv 'rate(requests_total%5B1m%5D)'
echo "rate[5m]  →"; qv 'rate(requests_total%5B5m%5D)'
echo "irate[1m] →"; qv 'irate(requests_total%5B1m%5D)'
echo "increase[5m] → (5분 × 10 = 300이어야?)"; qv 'increase(requests_total%5B5m%5D)'
```

예상: rate는 10에 가깝지만 정확히 10이 아니고, `increase[5m]`은 300.xx 같은 **소수점**이 나옵니다. ✅ 외삽(extrapolation) 때문입니다 — 창 경계와 샘플 위치가 어긋나므로 Prometheus는 기울기로 창 끝까지 연장합니다(theory §4). "요청 300.0004건"이 버그가 아닌 이유.

```bash
echo "--- 짧은 창의 함정: 스크레이프 간격(기본 15~30s)의 4배 미만 ---"
qv 'rate(requests_total%5B30s%5D)'    # 샘플 2개 이하 → 빈 결과나 요동
echo "→ 비었거나 튀었다면: 창 ≥ 4 × 스크레이프 간격 규칙의 실증"
```

## Step 3. 카운터 리셋 보정 — 앱 재시작

```bash
$PROM wget -qO- 'http://localhost:9090/api/v1/query?query=requests_total' | \
  python3 -c "import json,sys; print('재시작 전 카운터:', json.load(sys.stdin)['data']['result'][0]['value'][1])"

kubectl -n mon delete pod counter --wait=true >/dev/null
kubectl -n mon apply -f - <<'EOF' >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: counter
  annotations: { prometheus.io/scrape: "true", prometheus.io/port: "8080" }
  labels: { app: counter }
spec:
  containers:
    - name: app
      image: python:3.12-slim
      command: ["python","/src/app.py"]
      volumeMounts: [{ name: src, mountPath: /src }]
  volumes: [{ name: src, configMap: { name: counter-app } }]
EOF
kubectl -n mon wait --for=condition=ready pod/counter --timeout=120s
sleep 120

echo "재시작 후 rate[5m] (카운터가 0으로 리셋됐는데?) →"; qv 'rate(requests_total%5B5m%5D)'
echo "→ 음수가 아닙니다! rate가 리셋을 감지해 보정했습니다 (theory §4)"
echo "반면 절대값을 그냥 보면:"; qv 'requests_total'
echo "→ 카운터의 절대값은 의미 없습니다 — 언제든 리셋될 수 있으므로 rate/increase로만"
```

✅ 카운터의 절대값을 대시보드에 그리는 것이 왜 무의미한지의 실증.

## Step 4. 히스토그램 — 분위수는 평균낼 수 없습니다

```bash
cat <<'EOF'
# 잘못된 p99 (인스턴스별 분위수를 평균) — 수학적으로 무의미
avg(http_request_duration_seconds{quantile="0.99"})        ❌ (summary 타입)

# 올바른 p99 (버킷을 합산한 뒤 분위수 계산)
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))   ✅

이유: 분위수는 분포의 순서 통계량이라 선형 결합이 불가능합니다.
      "A인스턴스 p99=100ms, B인스턴스 p99=200ms" → 전체 p99는 150ms가 아닙니다.
      버킷(le)은 카운트라 합산 가능 → 합산 후 보간해야 옳습니다.
정확도: histogram_quantile은 버킷 경계 사이를 선형 보간 — 버킷 설계가 나쁘면 p99도 나쁩니다
        (네이티브 히스토그램이 이 한계를 개선하는 방향)
EOF
```

## Step 5. relabeling — 대상 선별과 주소 가공

```bash
$PROM wget -qO- 'http://localhost:9090/api/v1/targets' | python3 -c "
import json,sys
for t in json.load(sys.stdin)['data']['activeTargets'][:5]:
    print(f\"  {t['health']:6s} {t['labels'].get('job','?'):22s} {t['scrapeUrl']}\")"
```

예상: `up`인 대상들과 그 URL. 이 목록이 어떻게 만들어졌는지가 relabel_configs입니다:

```bash
$PROM cat /etc/config/prometheus.yml 2>/dev/null | \
  python3 -c "
import sys,re
cfg = sys.stdin.read()
# kubernetes-pods job의 relabel 부분만 발췌
m = re.search(r'- job_name: kubernetes-pods(.*?)(?=\n  - job_name:|\Z)', cfg, re.S)
print(m.group(0)[:1200] if m else '(job 없음)')"
```

✅ `__meta_kubernetes_pod_annotation_prometheus_io_scrape`를 `keep`으로 필터하고, `__address__`를 포트로 재작성하는 그 규칙 — **어노테이션 하나로 스크레이프가 켜지는 마법의 실체**(theory §5).

## Step 6. relabel 실험 — 대상을 골라내기

```bash
# counter Pod만 남기고 나머지 kubernetes-pods 대상을 drop하는 규칙 예시
cat <<'EOF'
relabel_configs:                       # 스크레이프 '전' — 대상 단계
  - source_labels: [__meta_kubernetes_pod_label_app]
    action: keep
    regex: counter                     # app=counter 인 Pod만
  - source_labels: [__meta_kubernetes_namespace]
    target_label: ns                   # 메타 라벨을 실제 라벨로 승격

metric_relabel_configs:                # 스크레이프 '후' — 샘플 단계 (lab-01의 방어선)
  - source_labels: [__name__]
    action: drop
    regex: "go_.*|process_.*"          # 런타임 메트릭 버리기 (카디널리티 절감)

★ 두 단계의 차이를 기억하세요:
   relabel_configs        = "누구를 긁을까" (대상이 사라지면 up 메트릭도 없음)
   metric_relabel_configs = "무엇을 저장할까" (긁긴 했으나 버림)
EOF
```

## Step 7. 분화 판단 — 언제 Thanos인가

```bash
echo "=== 현재 규모 지표 ==="
qv 'prometheus_tsdb_head_series'
qv 'prometheus_tsdb_storage_blocks_bytes'
cat <<'EOF'

분화 판단(theory §6):
  보존이 부족? (로컬 디스크로 3개월이 안 됨)   → Thanos sidecar + 오브젝트 스토리지
  전역 뷰 필요? (클러스터·샤드 통합 질의)      → Thanos Query
  HA 필요? (Prometheus 2대 중복 스크레이프)   → Thanos의 중복 제거
  단일 인스턴스 한계? (수백만 시계열)          → 샤딩(hashmod) + 전역 질의

★ 그 전에 반드시: promtool tsdb analyze 로 카디널리티 정리 (lab-01)
  "Prometheus가 부족하다"의 대부분은 "라벨을 잘못 붙였다"입니다
EOF
```

## 정리

```bash
bash cleanup.sh
```
