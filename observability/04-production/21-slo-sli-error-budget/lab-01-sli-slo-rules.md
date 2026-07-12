# Lab 01 — SLI 정의 → SLO recording rules → 버짓 계산

> 08의 스택 위에 SLO 체계를 recording rules로 구축합니다 — SLI 계층(rate5m~rate3d), 버짓 잔량 계산, SLO 대시보드의 재료까지.

## 0. 준비 — 08 구성 재현

```bash
kind create cluster --name slo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null; helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --set prometheus.prometheusSpec.retention=3d

# payment 앱 + SM (08·10과 동일 세트)
kubectl create namespace shop
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: payment, namespace: shop }
spec:
  replicas: 2
  selector: { matchLabels: { app: payment } }
  template:
    metadata: { labels: { app: payment } }
    spec:
      containers:
        - name: app
          image: quay.io/brancz/prometheus-example-app:v0.5.0
          ports: [{ name: http, containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: payment, namespace: shop, labels: { app: payment } }
spec: { selector: { app: payment }, ports: [{ name: metrics, port: 8080 }] }
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: { name: payment, namespace: shop, labels: { release: monitoring } }
spec:
  selector: { matchLabels: { app: payment } }
  endpoints: [{ port: metrics, interval: 15s }]
EOF

# 평시 트래픽: 성공 위주 + 낮은 에러 (SLO 산정의 "과거 실적" 만들기)
kubectl -n shop run baseline --image=curlimages/curl --restart=Never -- sh -c '
  while true; do
    for i in $(seq 1 50); do curl -s http://payment:8080/ >/dev/null; done;
    curl -s http://payment:8080/err >/dev/null;      # ~2% 에러
    sleep 1;
  done'
sleep 300   # 실적 축적
```

## 1. 과거 실적 측정 — SLO는 데이터에서

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3

# 우리의 실제 성공률은?
curl -s 'localhost:9090/api/v1/query?query=1-(sum(rate(http_requests_total{namespace="shop",code=~"5.."}[30m]))/sum(rate(http_requests_total{namespace="shop"}[30m])))' \
  | grep -o '"value":\[[^]]*\]'
# 예: 0.980 (98.0%)

# 산정 판단(theory 2절): 실적 98% → SLO는 지킬 수 있는 97%에서 시작?
# 실습에선 계산이 선명하도록 SLO = 98% (허용 실패율 2%)로 설정
```

## 2. SLI 계층 — recording rules

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: payment-slo
  namespace: shop
  labels: { release: monitoring }
spec:
  groups:
    - name: slo.sli
      interval: 30s
      rules:
        # 에러 비율의 창 계층 (번레이트의 재료 — lab-02)
        - record: slo:payment_error_ratio:rate5m
          expr: |
            sum(rate(http_requests_total{namespace="shop",code=~"5.."}[5m]))
            / sum(rate(http_requests_total{namespace="shop"}[5m]))
        - record: slo:payment_error_ratio:rate30m
          expr: |
            sum(rate(http_requests_total{namespace="shop",code=~"5.."}[30m]))
            / sum(rate(http_requests_total{namespace="shop"}[30m]))
        - record: slo:payment_error_ratio:rate1h
          expr: |
            sum(rate(http_requests_total{namespace="shop",code=~"5.."}[1h]))
            / sum(rate(http_requests_total{namespace="shop"}[1h]))
        - record: slo:payment_error_ratio:rate6h
          expr: |
            sum(rate(http_requests_total{namespace="shop",code=~"5.."}[6h]))
            / sum(rate(http_requests_total{namespace="shop"}[6h]))
    - name: slo.budget
      interval: 60s
      rules:
        # 기간(실습: 1일) 누적 실패와 버짓 잔량 비율
        - record: slo:payment_errors:increase1d
          expr: sum(increase(http_requests_total{namespace="shop",code=~"5.."}[1d]))
        - record: slo:payment_requests:increase1d
          expr: sum(increase(http_requests_total{namespace="shop"}[1d]))
        # 버짓 사용률 = 누적 실패 / (허용 실패율 0.02 × 전체)
        - record: slo:payment_budget_used_ratio:1d
          expr: |
            slo:payment_errors:increase1d
            / (0.02 * slo:payment_requests:increase1d)
EOF
sleep 90
```

**정의 문서화(08의 교훈)** — 분모: 전체 요청, 분자: 5xx만(4xx 제외 — 사용자 원인으로 간주, 예외는 리뷰로). 이 결정이 rule 주석·문서에 남아야 "같은 이름 다른 수식" 사고를 막습니다.

## 3. 버짓 잔량 읽기

```bash
curl -s 'localhost:9090/api/v1/query?query=slo:payment_budget_used_ratio:1d' | grep -o '"value":\[[^]]*\]'
# 예: 0.95 → "1일 버짓의 95%를 사용" (2% 에러가 허용 실패율 2%에 근접하므로)

# 해석 훈련:
#  < 1.0: 버짓 내 — 릴리즈 가능
#  > 1.0: SLO 위반 상태 — 안정화 모드 (조직 계약 발동!)
```

**대시보드 재료(09)** — 이 세 시계열로 SLO 패널 구성: ① 버짓 사용률 게이지(임계 0.5/1.0 색), ② error_ratio 추세와 SLO 선(0.02), ③ (lab-02 후) 번레이트. L1 개요(09)에 서비스별 버짓 잔량 열을 추가하면 "어디가 아픈가"가 "어디 버짓이 급한가"로 진화합니다.

## 4. 지연 SLI 추가 (03의 결실 확인)

```bash
# 예제 앱의 histogram 버킷 확인 — SLO 경계가 버킷에 있는가요?
curl -s 'localhost:9090/api/v1/query?query=http_request_duration_seconds_bucket{namespace="shop"}' \
  | grep -o 'le":"[^"]*"' | sort -u | head
# le: 0.0001 ... 0.001 ... 0.1 ...
# → "0.1s 이내 비율 ≥ 99%"로 SLO를 세운다면 le="0.1" 버킷이 분자:
#   sum(rate(..._bucket{le="0.1"}[5m])) / sum(rate(..._count[5m]))
# → 만약 경계 0.3을 원하는데 버킷에 없다면? 근사 오차 — 계측의 버킷을
#   고쳐야 합니다 (03: "버킷 설계 = SLO 설계"의 실증)
```

## 5. 정리

```bash
kill %1 2>/dev/null || true
# 클러스터·트래픽은 lab-02(번레이트 알림)에서 계속
```

## 정리

- SLO는 과거 실적 측정에서 시작 — 지킬 수 있는 약속부터
- SLI 창 계층(5m~6h)을 recording rules로 — 번레이트(lab-02)의 재료이자 정의 단일화
- 버짓 사용률 = 누적 실패 / 허용 실패량 — 1.0이 조직 계약의 발동선
- 지연 SLI는 le=경계 버킷 — 경계가 버킷에 없으면 계측을 고칩니다 (03의 완성)
- **★ SLO 체계 = 08(rules) 위의 한 층 — 새 도구가 아니라 규율의 조합**
