# Lab 01 — 4형 노출과 rate의 감각

> 메트릭을 노출하는 앱을 직접 돌려 4형의 노출 형식을 눈으로 읽고, counter를 그대로 볼 때와 rate로 볼 때의 차이를 손으로 계산해 "counter는 rate로"의 감각을 몸에 새깁니다.

## 0. 준비

```bash
kind create cluster --name metrics
```

## 1. 메트릭을 노출하는 앱 배포

Prometheus 생태계의 표준 예제 앱을 씁니다:

```bash
# prom/prometheus-example-app 또는 간단한 nginx-exporter 조합 대신
# 4형이 모두 보이는 앱: prometheus의 예제
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: metric-app }
spec:
  replicas: 1
  selector: { matchLabels: { app: metric-app } }
  template:
    metadata: { labels: { app: metric-app } }
    spec:
      containers:
        - name: app
          image: quay.io/brancz/prometheus-example-app:v0.5.0
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: metric-app }
spec:
  selector: { app: metric-app }
  ports: [{ port: 8080 }]
EOF
kubectl wait deploy/metric-app --for=condition=Available --timeout=120s
```

## 2. 노출 형식 읽기

```bash
# 트래픽을 조금 만들고
kubectl run gen --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in $(seq 1 50); do curl -s http://metric-app:8080/ >/dev/null; curl -s http://metric-app:8080/err >/dev/null; sleep 0.1; done'
sleep 15

# /metrics를 직접 읽습니다
kubectl run reader --image=curlimages/curl --restart=Never --rm -it -- \
  curl -s http://metric-app:8080/metrics | head -40
```

출력에서 찾아 읽을 것:

```
# TYPE http_requests_total counter          ← counter 선언
http_requests_total{code="200",method="get"} 50
http_requests_total{code="404",method="get"} 50
  → 이름 + 라벨(code·method) + 값. 라벨 조합마다 별도 시계열!

# TYPE http_request_duration_seconds histogram   ← histogram
http_request_duration_seconds_bucket{le="0.0001"} 3
http_request_duration_seconds_bucket{le="0.001"} 48
http_request_duration_seconds_bucket{le="+Inf"} 100
http_request_duration_seconds_sum 0.1234
http_request_duration_seconds_count 100
  → 버킷(누적!) + 합계 + 개수. 평균 = sum/count
  → le=0.001의 48 = "1ms 이하가 48건" (0.0001 이하 3건 포함 누적)
```

**확인 질문 (직접 계산)** — 위 예시에서 1ms 초과 요청은 몇 건인가요? → count(100) - le=0.001(48) = 52건. 버킷이 **누적**이라는 감각이 핵심입니다.

## 3. counter를 그대로 보면 — 우상향의 무의미

```bash
# 30초 간격으로 두 번 스냅샷
kubectl run snap1 --image=curlimages/curl --restart=Never --rm -it -- \
  sh -c 'curl -s http://metric-app:8080/metrics | grep "^http_requests_total"'
# http_requests_total{code="200",...} 50

# 트래픽 더 발생
kubectl run gen2 --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in $(seq 1 120); do curl -s http://metric-app:8080/ >/dev/null; sleep 0.25; done'
sleep 30

kubectl run snap2 --image=curlimages/curl --restart=Never --rm -it -- \
  sh -c 'curl -s http://metric-app:8080/metrics | grep "^http_requests_total"'
# http_requests_total{code="200",...} 170
```

**손으로 rate 계산** — (170-50) / 30s = **4 req/s**. 이것이 `rate(http_requests_total[30s])`가 하는 일의 전부입니다: 창 안의 증가분 ÷ 시간. counter의 절대값(170)은 "재시작 후 누적"일 뿐이고, 의미는 언제나 증가 속도에 있습니다.

## 4. 리셋 실험 — rate가 재시작을 이기는 법

```bash
# 앱을 재시작 → counter가 0으로
kubectl rollout restart deploy/metric-app
kubectl rollout status deploy/metric-app --timeout=60s

kubectl run snap3 --image=curlimages/curl --restart=Never --rm -it -- \
  sh -c 'curl -s http://metric-app:8080/metrics | grep "^http_requests_total" | head -2'
# http_requests_total{...} 0   ← 리셋!
```

**개념 확인** — 그래프로 보면 170 → 0으로 떨어지는 절벽. 소박한 차분 계산은 음수(-170)가 되지만, `rate()`는 "counter는 단조 증가"라는 계약을 알기에 하락 지점을 리셋으로 인식하고 0부터의 증가로 보정합니다. **타입이 계약이고, 계약이 있어야 도구가 올바로 해석합니다** — TYPE 선언이 장식이 아닌 이유.

## 5. 라벨 폭발 미리 체험 (계산만)

```bash
# 이 앱의 시계열 수를 세어 보라
kubectl run counter --image=curlimages/curl --restart=Never --rm -it -- \
  sh -c 'curl -s http://metric-app:8080/metrics | grep -v "^#" | wc -l'
# 예: 40개 안팎 (건강)
```

**사고 실험** — 여기에 `user_id` 라벨(유저 10만 명)을 붙이면? 40 × 100,000 = 400만 시계열/인스턴스. Prometheus 메모리는 시계열 수에 비례합니다(cncf 11) — 인스턴스 하나가 서버를 삼킵니다. **unbounded 값은 라벨 금지**의 감각을 숫자로 기억하세요.

## 6. 정리

```bash
kubectl delete deploy metric-app
kubectl delete svc metric-app
kubectl delete pod gen gen2 --force --grace-period=0 2>/dev/null || true
# 클러스터는 lab-02에서 계속
```

## 정리

- 노출 형식: `이름{라벨} 값` + HELP/TYPE — 라벨 조합마다 별도 시계열
- histogram 버킷은 **누적**(le 이하 전부) — 초과분은 count에서 빼서 계산
- counter의 절대값은 무의미 — rate = 창 안 증가분 ÷ 시간 (손으로 계산해 봄)
- 재시작 리셋을 rate가 보정하는 근거 = TYPE 계약("counter는 단조 증가")
- 시계열 수 = 라벨 조합의 곱 — unbounded 라벨 하나가 서버를 삼킵니다
- **★ 타입은 "이 숫자를 어떻게 읽는가"의 계약 — 계약을 알아야 숫자가 정보가 됩니다**
