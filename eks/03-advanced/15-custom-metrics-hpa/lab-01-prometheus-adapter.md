# Lab 01 — custom.metrics API 개통: Prometheus + Adapter + HPA

부품이 전부 보이는 정통 경로를 손으로 잇습니다: 앱 카운터 → scrape → rate 번역 → 메트릭 API → HPA. 어디가 끊겨도 진단할 수 있게 되는 것이 목표입니다.

## Step 1. 표적 — 메트릭을 말하는 앱

```bash
kubectl create ns scalelab
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: podinfo, namespace: scalelab }
spec:
  replicas: 2
  selector: { matchLabels: { app: podinfo } }
  template:
    metadata:
      labels: { app: podinfo }
      annotations:                          # Prometheus에게 "나를 긁어라"
        prometheus.io/scrape: "true"
        prometheus.io/port: "9898"
    spec:
      containers:
      - name: podinfo
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        ports: [{ containerPort: 9898 }]
        resources: { requests: { cpu: 100m, memory: 64Mi } }
        readinessProbe: { httpGet: { path: /readyz, port: 9898 } }
---
apiVersion: v1
kind: Service
metadata: { name: podinfo, namespace: scalelab }
spec:
  selector: { app: podinfo }
  ports: [{ port: 9898 }]
EOF
kubectl rollout status deploy/podinfo -n scalelab

# 앱이 내는 원료 확인 — 누적 카운터 (단조 증가)
kubectl exec -n scalelab deploy/podinfo -- sh -c "wget -qO- localhost:9898/metrics" | grep http_request_duration_seconds_count | head -3
```

✅ `http_request_duration_seconds_count{...} N` — RPS의 원료는 이 **누적값**입니다. rate()가 이걸 초당 증가율로 바꿉니다.

## Step 2. Prometheus 최소 설치 (본격 운영은 cncf 파트에서)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/prometheus -n monitoring --create-namespace \
  --set alertmanager.enabled=false \
  --set prometheus-pushgateway.enabled=false \
  --set prometheus-node-exporter.enabled=false \
  --set server.persistentVolume.enabled=false
kubectl rollout status deploy/prometheus-server -n monitoring --timeout=180s
```

scrape가 도는지 쿼리로 검증 (annotation 발견 → 자동 수집):

```bash
kubectl run q --rm -i --restart=Never -n monitoring --image=curlimages/curl -- -s \
  "http://prometheus-server/api/v1/query?query=rate(http_request_duration_seconds_count{namespace=\"scalelab\"}[1m])" \
  | head -c 600; echo
```

예상: podinfo Pod 라벨이 붙은 시계열 (지금은 값 ~0 — 트래픽이 없으니).

## Step 3. Adapter — 번역 규칙 한 장

```bash
cat > adapter-values.yaml <<'EOF'
prometheus:
  url: http://prometheus-server.monitoring.svc
  port: 80
rules:
  default: false
  custom:
  - seriesQuery: 'http_request_duration_seconds_count{namespace!="",pod!=""}'
    resources:
      overrides:
        namespace: { resource: namespace }
        pod: { resource: pod }
    name:
      matches: "^(.*)_count$"
      as: "http_requests_per_second"          # HPA가 부를 이름
    metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[1m])) by (<<.GroupBy>>)'
EOF
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  -n monitoring -f adapter-values.yaml
kubectl rollout status deploy/prometheus-adapter -n monitoring --timeout=180s
```

규칙의 세 문장: **어떤 시계열을**(seriesQuery) / **어떻게 가공해**(metricsQuery — rate 1분) / **무슨 이름으로**(http_requests_per_second).

## Step 4. 개통 검증 — HPA가 볼 바로 그 창을 우리가 먼저 봅니다

```bash
# APIService 등록 확인 (k8s 29의 aggregated API)
kubectl get apiservice v1beta1.custom.metrics.k8s.io

# HPA와 똑같은 방식으로 raw 조회
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/scalelab/pods/*/http_requests_per_second" \
  | python3 -m json.tool | grep -E '"name"|"value"'
```

예상: Pod 2개 각각 value `0` 안팎. ✅ **이 명령이 이 경로 전체의 디버깅 도구입니다** — HPA가 "unknown"을 보이면 여기부터 거꾸로(어댑터 로그 → Prometheus 쿼리 → scrape annotation) 짚습니다.

## Step 5. RPS HPA — 13의 숫자를 목표로

target은 자기 측정값으로: `(무릎 ÷ 측정 replicas) × 0.7`. 아래는 실험 가시성을 위한 예시값(50):

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: podinfo-rps, namespace: scalelab }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: podinfo }
  minReplicas: 2
  maxReplicas: 8
  metrics:
  - type: Pods
    pods:
      metric: { name: http_requests_per_second }
      target: { type: AverageValue, averageValue: "50" }   # ← Pod당 목표 (13에서 산정)
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies: [{ type: Percent, value: 100, periodSeconds: 30 }]
    scaleDown:
      stabilizationWindowSeconds: 300
      policies: [{ type: Pods, value: 1, periodSeconds: 60 }]
EOF
kubectl get hpa -n scalelab podinfo-rps    # TARGETS: 0/50 — 개통 (unknown이면 Step 4로)
```

## Step 6. 발화 실험 — 300 rps를 부어봅니다

터미널 1 (감시):

```bash
kubectl get hpa podinfo-rps -n scalelab -w
```

터미널 2 (부하 — 13의 open 모델):

```bash
kubectl run vegeta --rm -i --restart=Never -n scalelab \
  --image=peterevans/vegeta:latest --requests=cpu=500m -- sh -c \
  "echo 'GET http://podinfo.scalelab.svc:9898/' | vegeta attack -rate=300 -duration=240s | vegeta report"
```

터미널 1 예상 진행:

```
TARGETS        REPLICAS
0/50           2
150/50         2        ← 메트릭 도착 (~30s 지연): Pod당 150
150/50         6        ← ceil(2×150/50)=6 — HPA 공식 그대로!
~50/50         6        ← 6개로 나눠지니 Pod당 ≈50: 평형
```

부하가 끝나면: TARGETS 0/50이지만 REPLICAS는 **5분간 6 유지** 후 한 대씩 감소 — behavior의 "감축은 신중히"가 작동하는 모습.

✅ 세 가지를 눈으로 확인했습니다: ① 공식의 산수(2×150/50=6) ② 메트릭 지연 30~60s — target에 쿠션(×0.7)이 필요한 이유 ③ 비대칭 behavior.

## 정리

Prometheus/podinfo는 lab-02가 이어 씁니다. HPA만 제거 (lab-02에서 KEDA가 자기 HPA를 만듭니다 — 이중 조종 금지):

```bash
kubectl delete hpa podinfo-rps -n scalelab
```
