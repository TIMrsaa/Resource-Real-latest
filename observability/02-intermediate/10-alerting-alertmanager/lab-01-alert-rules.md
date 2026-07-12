# Lab 01 — 알림 규칙: 작성과 발화의 해부

> 좋은 알림 하나를 처음부터 끝까지 만듭니다 — recording rule 위에, for와 함께, runbook·대시보드 링크를 갖춰. 그리고 pending→firing의 상태 전이와 "없음의 감지"(absent)를 관찰합니다.

## 0. 준비 — 08·09의 스택 재구축

```bash
kind create cluster --name alerts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null; helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --set prometheus.prometheusSpec.retention=24h

# payment 앱 + ServiceMonitor + 에러 트래픽 (09 lab-01과 동일 세트 축약)
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
spec:
  selector: { app: payment }
  ports: [{ name: metrics, port: 8080 }]
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: { name: payment, namespace: shop, labels: { release: monitoring } }
spec:
  selector: { matchLabels: { app: payment } }
  endpoints: [{ port: metrics, interval: 15s }]
EOF
```

## 1. 기반: recording rule 먼저 (08의 규율)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: payment-rules
  namespace: shop
  labels: { release: monitoring }
spec:
  groups:
    - name: payment.record
      interval: 30s
      rules:
        - record: job:http_error_ratio:rate5m
          expr: |
            sum by (job) (rate(http_requests_total{code=~"5.."}[5m]))
            / sum by (job) (rate(http_requests_total[5m]))
EOF
```

## 2. 알림 규칙 — 3심사를 갖춰서

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: payment-alerts
  namespace: shop
  labels: { release: monitoring }
spec:
  groups:
    - name: payment.alerts
      rules:
        # 심사 ① 증상 기반 (에러율 — 사용자 영향)
        - alert: PaymentHighErrorRate
          expr: job:http_error_ratio:rate5m{job="payment"} > 0.3
          for: 3m                                    # 지속 확인 (실습이라 짧게)
          keep_firing_for: 2m
          labels:
            severity: page                           # 심사 ③ 긴급성
            team: commerce
          annotations:                               # 심사 ② 행동 가능
            summary: "payment 에러율 {{ $value | humanizePercentage }} — 3분 지속"
            dashboard: "http://localhost:3000/d/svc-red?var-service=payment"
            runbook: "https://runbooks.example/payment-errors"
        # "없음"의 감지 — 조용한 실패 방지 (08)
        - alert: PaymentTargetMissing
          expr: absent(up{job="payment"})
          for: 5m
          labels: { severity: page, team: commerce }
          annotations:
            summary: "payment 스크레이프 타깃이 사라짐 (SM 매칭? 배포?)"
EOF
```

## 3. 발화 관찰 — pending → firing

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3

# 평시: inactive 확인
curl -s localhost:9090/api/v1/rules | grep -A2 PaymentHighErrorRate | grep state
# "state":"inactive"

# 에러 트래픽 주입 (에러율 50%)
kubectl -n shop run bad-traffic --image=curlimages/curl --restart=Never -- sh -c '
  while true; do curl -s http://payment:8080/ >/dev/null; curl -s http://payment:8080/err >/dev/null; sleep 0.2; done'

# 1~2분 뒤: pending (조건 참, for 대기 중)
sleep 90
curl -s localhost:9090/api/v1/alerts | grep -o '"state":"[a-z]*"' | sort | uniq -c
# "state":"pending"   ← 조건은 참인데 아직 안 울림 — 스파이크 필터 작동 중

# for(3m) 경과 후: firing
sleep 150
curl -s localhost:9090/api/v1/alerts | grep -B2 -A8 PaymentHighErrorRate | head -20
# "state":"firing", labels(severity=page), annotations(대시보드·runbook) 확인
```

**해부** — pending 상태가 for의 실체입니다: "참이지만 아직 지속 확인 중". 배포 직후 10초 스파이크였다면 pending에서 inactive로 돌아가 소음이 되지 않았을 것. firing 알림에는 severity(라우팅 재료)·summary(값 포함)·dashboard·runbook(다음 행동)이 실려 있습니다 — 3심사의 물증.

## 4. 회복과 keep_firing_for

```bash
# 에러 트래픽 중단
kubectl -n shop delete pod bad-traffic --force --grace-period=0
# 정상 트래픽만 재개
kubectl -n shop run good-traffic --image=curlimages/curl --restart=Never -- sh -c '
  while true; do curl -s http://payment:8080/ >/dev/null; sleep 0.2; done'

sleep 120
curl -s localhost:9090/api/v1/alerts | grep -c firing || echo "0 (또는 keep_firing 잔류)"
# keep_firing_for(2m) 동안은 firing 유지 → 이후 resolve
# → 경계 근처에서 fire/resolve가 널뛰는 플래핑(알림 스팸의 단골)을 방지
```

## 5. "없음"의 알림 검증

```bash
# ServiceMonitor의 release 라벨 제거 (08 lab-01의 조용한 실패 재현)
kubectl -n shop label servicemonitor payment release-
sleep 360   # absent + for 5m

curl -s localhost:9090/api/v1/alerts | grep -A3 PaymentTargetMissing | grep state
# "state":"firing"   ← 조용한 미수집이 시끄러워졌습니다!

kubectl -n shop label servicemonitor payment release=monitoring   # 복구
```

**의미** — 08에서 겪은 "조용한 미수집"이 이제 알림이 됩니다. 관측 체계 자체의 구멍(타깃 소실·rule 미평가·수집기 드롭)을 감시하는 알림들이 "관측의 관측"(22)의 뼈대입니다.

## 6. 정리

```bash
kill %1 2>/dev/null || true
# 클러스터는 lab-02에서 계속 (알림 발화 상태 유지를 위해 bad-traffic 재주입)
kubectl -n shop run bad-traffic --image=curlimages/curl --restart=Never -- sh -c '
  while true; do curl -s http://payment:8080/err >/dev/null; sleep 0.2; done'
```

## 정리

- 좋은 알림의 물증: recording rule 위 + for + severity + summary(값)·dashboard·runbook
- pending = for의 실체 (스파이크 필터), keep_firing_for = 플래핑 방지
- absent(up{job=...})로 "없음"을 알림화 — 조용한 실패(08)의 해독제
- 알림도 PrometheusRule CRD = GitOps 관리 — 추가·삭제가 PR 심사
- **★ 울릴 자격(3심사)을 갖춘 알림만 만들 것 — 알림은 미래의 인터럽트라는 빚입니다**
