# Lab 01 — KEDA가 만든 HPA를 열어보고, 두 문턱을 실험합니다

"KEDA는 HPA를 대체하지 않는다"를 오브젝트와 API로 확인하고, activation과 scaling의 차이를 눈으로 봅니다.

전제: kind, kubectl, helm.

## Step 1. 클러스터와 KEDA

```bash
kind create cluster --name keda -q
helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1
helm install keda kedacore/keda -n keda --create-namespace >/dev/null
kubectl -n keda rollout status deploy/keda-operator --timeout=180s
kubectl -n keda rollout status deploy/keda-operator-metrics-apiserver --timeout=180s

kubectl -n keda get deploy
echo "→ operator(스케일러 폴링·HPA 관리) + metrics-apiserver(통역사) + admission(검증)"
```

## Step 2. 관측 대상 + Prometheus (스케일 신호원)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
helm install prom prometheus-community/prometheus -n mon --create-namespace \
  --set alertmanager.enabled=false --set prometheus-pushgateway.enabled=false \
  --set server.persistentVolume.enabled=false >/dev/null
kubectl -n mon rollout status deploy/prom-prometheus-server --timeout=300s

# 스케일 대상
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  labels: { app: worker }
spec:
  replicas: 0                        # 시작은 0개 — KEDA가 깨울 대상
  selector:
    matchLabels: { app: worker }
  template:
    metadata:
      labels: { app: worker }
    spec:
      containers:
        - name: worker
          image: busybox
          command: ["sh", "-c", "while true; do sleep 5; done"]
EOF
```

## Step 3. ScaledObject 생성 — 그리고 HPA가 나타납니다

```bash
kubectl apply -f - <<'EOF'
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: worker-so }
spec:
  scaleTargetRef: { name: worker }
  minReplicaCount: 0
  maxReplicaCount: 10
  pollingInterval: 15
  cooldownPeriod: 60
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prom-prometheus-server.mon.svc:80
        query: sum(prometheus_http_requests_total)     # 아무 메트릭 (계속 증가)
        threshold: "500"                # ★ scaling: Pod 하나가 500을 담당
        activationThreshold: "100"      # ★ activation: 100 넘어야 0→1
EOF
sleep 30

echo "=== ★ KEDA가 HPA를 만들었다 ==="
kubectl get hpa
kubectl get hpa -o jsonpath='{.items[0].metadata.name}'; echo
kubectl get hpa -o jsonpath='{.items[0].spec.metrics[0].type}'; echo
```

예상: `keda-hpa-worker-so`라는 HPA, type이 `External`. ✅ **스케일 계산은 여전히 HPA가 합니다**(theory §1) — KEDA는 통역사이자 0↔1 담당입니다.

## Step 4. External Metrics API — 통역사의 실물

```bash
echo "=== KEDA가 등록한 External Metrics API ==="
kubectl get apiservice | grep external.metrics
echo ""
echo "=== HPA가 묻는 그 API를 직접 호출 ==="
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1" | python3 -m json.tool | head -12
```

✅ `v1beta1.external.metrics.k8s.io` APIService가 keda-metrics-apiserver를 가리킵니다 — HPA는 표준 API로 물을 뿐이고, 답하는 것이 KEDA입니다.

## Step 5. 두 문턱의 동작 확인

```bash
echo "=== 현재 메트릭 값과 replicas ==="
kubectl get scaledobject worker-so
kubectl describe hpa keda-hpa-worker-so 2>/dev/null | grep -A3 "Metrics:" | head -4
kubectl get deploy worker -o jsonpath='{.spec.replicas}'; echo " replicas"

cat <<'EOF'

두 문턱 (theory §2):
  activationThreshold=100 : 메트릭이 100 이하면 replicas 0 (KEDA가 결정)
  threshold=500           : 100 초과 시 HPA가 desired = ceil(metric/500) 계산

예: 메트릭 1,347 → activation 통과 → ceil(1347/500) = 3 replicas
    메트릭 50    → activation 미달 → 0 replicas (Pod 없음)
    메트릭 0     → 0 replicas + cooldownPeriod 후 스케일다운
EOF

sleep 60
echo ""
echo "60초 후 상태:"
kubectl get deploy worker
kubectl describe hpa keda-hpa-worker-so 2>/dev/null | tail -5
```

## Step 6. scale-to-zero의 콜드스타트 측정

```bash
# 강제로 0으로 (메트릭을 넘지 못하는 쿼리로 교체)
kubectl patch scaledobject worker-so --type merge -p \
  '{"spec":{"triggers":[{"type":"prometheus","metadata":{"serverAddress":"http://prom-prometheus-server.mon.svc:80","query":"vector(0)","threshold":"500","activationThreshold":"100"}}]}}'
echo "cooldownPeriod(60s) 대기..."
sleep 90
kubectl get deploy worker -o jsonpath='{.spec.replicas}'; echo " replicas (0이어야 정상)"

# 신호를 켜고 0→1 시간 측정
START=$(date +%s)
kubectl patch scaledobject worker-so --type merge -p \
  '{"spec":{"triggers":[{"type":"prometheus","metadata":{"serverAddress":"http://prom-prometheus-server.mon.svc:80","query":"vector(1000)","threshold":"500","activationThreshold":"100"}}]}}'

while [ "$(kubectl get pod -l app=worker --no-headers 2>/dev/null | grep -c Running)" -lt 1 ]; do
  sleep 2
  [ $(( $(date +%s) - START )) -gt 180 ] && break
done
echo "0 → Running 까지: $(( $(date +%s) - START ))초"
```

예상: 폴링 간격(15초) + 스케줄 + 이미지(캐시됨) ≈ 20~40초. ✅ **콜드스타트의 실체** — 실전에서는 여기에 이미지 pull(수십 초)과 노드 프로비저닝(1~2분, eks 17)이 더해집니다(theory §5).

## Step 7. 진단 4층 확인

```bash
echo "=== ① 스케일러가 신호를 읽는가 ==="
kubectl get scaledobject worker-so -o jsonpath='{.status.conditions}' | python3 -m json.tool 2>/dev/null | head -12
kubectl -n keda logs deploy/keda-operator --tail=20 | grep -iE "error|scaler" | head -3

echo ""
echo "=== ② metrics-adapter가 답하는가 ==="
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/default/s0-prometheus?labelSelector=scaledobject.keda.sh%2Fname%3Dworker-so" 2>/dev/null | head -c 300; echo

echo ""
echo "=== ③ HPA가 계산하는가 ==="
kubectl describe hpa keda-hpa-worker-so | grep -E "Metrics:|Deployment pods:|Conditions:" -A2 | head -8

echo ""
echo "=== ④ Pod가 스케줄되는가 ==="
kubectl get pod -l app=worker -o wide
kubectl get events --field-selector reason=FailedScheduling --sort-by=.lastTimestamp | tail -2
```

✅ 네 층 각각에 확인 명령이 있습니다 — "Pod가 안 뜬다"를 층으로 분해하는 것이 이 모듈의 실무 가치입니다(theory §6).

## Step 8. 산출물

```markdown
# KEDA 구조 카드
- ScaledObject → KEDA operator → HPA 생성(keda-hpa-<name>)
- HPA는 external.metrics.k8s.io로 KEDA metrics-adapter에 질의
- 스케일 계산: desired = ceil(metric / threshold)  ← HPA의 일
- 0↔1: activationThreshold + cooldownPeriod ← KEDA의 일
- 진단 4층: 스케일러 → adapter → HPA → 노드
- 콜드스타트 = 폴링 + 스케줄 + pull + 부팅 [+ 노드]
```

## 정리

lab-02에서 계속. 유지.
