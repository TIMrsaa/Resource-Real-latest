# Lab 01 — 스택 배포와 ServiceMonitor 등록

> kube-prometheus-stack을 배포하고, 03의 메트릭 앱을 ServiceMonitor로 등록해 "선언형 스크레이프"의 전 과정을 확인합니다. 매칭 3연쇄가 어긋났을 때의 조용한 실패도 일부러 겪습니다.

## 0. 준비

```bash
kind create cluster --name prom

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.retention=24h \
  --set prometheus.prometheusSpec.resources.requests.memory=400Mi

kubectl -n monitoring get pods
# prometheus-monitoring-...-0        (서버, StatefulSet)
# monitoring-kube-prometheus-operator-...  (두뇌)
# monitoring-kube-state-metrics-...  (KSM)
# monitoring-prometheus-node-exporter-... (DS)
# monitoring-grafana-...             (09에서)
# alertmanager-...-0                 (10에서)
```

## 1. 기본 수집 확인 — 이미 많은 것이 긁히고 있습니다

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3

# 타깃 목록 (UI 없이 API로)
curl -s localhost:9090/api/v1/targets | grep -o '"job":"[^"]*"' | sort | uniq -c
#  "job":"apiserver"          ← 컨트롤 플레인
#  "job":"kubelet"            ← cAdvisor 포함
#  "job":"kube-state-metrics"
#  "job":"node-exporter"
#  ... 기본 ServiceMonitor들이 이미 등록해 둠
```

**3대장 첫 질의** — 각 소스의 관점을 확인:

```bash
# KSM: "오브젝트 상태" — 네임스페이스별 Pod 수
curl -s 'localhost:9090/api/v1/query?query=count(kube_pod_info)%20by%20(namespace)' | head -c 300
# cAdvisor: "컨테이너 사용량"
curl -s 'localhost:9090/api/v1/query?query=sum(rate(container_cpu_usage_seconds_total[5m]))' | head -c 200
# node-exporter: "기계"
curl -s 'localhost:9090/api/v1/query?query=node_memory_MemAvailable_bytes' | head -c 200
```

## 2. 내 앱을 등록 — ServiceMonitor

```bash
# 03의 메트릭 앱 + Service (포트에 "이름"이 있어야 함!)
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
metadata:
  name: payment
  namespace: shop
  labels: { app: payment }
spec:
  selector: { app: payment }
  ports:
    - name: metrics          # ★ ServiceMonitor가 이 "이름"을 참조
      port: 8080
EOF

# ServiceMonitor — 매칭 3연쇄를 의식하며
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment
  namespace: shop
  labels:
    release: monitoring       # ① Prometheus의 serviceMonitorSelector와 일치
spec:
  selector:
    matchLabels:
      app: payment            # ② Service의 라벨과 일치
  endpoints:
    - port: metrics           # ③ Service 포트 "이름"과 일치
      interval: 15s
EOF

sleep 45
curl -s localhost:9090/api/v1/targets | grep -o '"job":"payment"' | head -1
# "job":"payment"   ← 자동 등록! (설정 파일 수정 없이)

# 트래픽 만들고 질의
kubectl -n shop run gen --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in $(seq 1 100); do curl -s http://payment:8080/ >/dev/null; sleep 0.2; done'
sleep 40
curl -s 'localhost:9090/api/v1/query?query=sum(rate(http_requests_total{namespace="shop"}[5m]))' | head -c 300
# → 초당 요청이 나옴 — 03의 rate가 실제 저장소 위에서!
```

**핵심** — 중앙 설정을 안 건드렸습니다. ServiceMonitor(앱 네임스페이스의 CRD)만으로 수집이 시작됐습니다 — 팀 셀프서비스의 실체. Pod 2개가 **개별 타깃**으로 잡힌 것도 확인하세요(인스턴스별 시계열 → sum으로 집계하는 이유).

## 3. 조용한 실패 체험 — 매칭 사슬 끊기

```bash
# ①번 사슬 절단: release 라벨 제거
kubectl -n shop label servicemonitor payment release-
sleep 45
curl -s localhost:9090/api/v1/targets | grep -c '"job":"payment"' || echo "0"
# 0   ← 타깃에서 사라짐. ★ 에러도 이벤트도 없습니다 — 조용한 미수집!

# 복구
kubectl -n shop label servicemonitor payment release=monitoring
sleep 45
curl -s localhost:9090/api/v1/targets | grep -c '"job":"payment"'
# 다시 등록
```

**교훈** — 매칭 실패는 조용합니다. "메트릭이 안 보여요"의 점검 순서: ① SM의 라벨 ↔ Prometheus selector(`kubectl get prometheus -o yaml | grep -A3 serviceMonitorSelector`), ② SM selector ↔ Service 라벨, ③ 포트 이름. 그리고 **없음의 감지**(`absent(up{job="payment"})`)를 알림으로 걸어야(10) 조용한 미수집이 "아는 미수집"이 됩니다.

## 4. up 메트릭 — 타깃 생사의 1차 신호

```bash
curl -s 'localhost:9090/api/v1/query?query=up{namespace="shop"}' | head -c 400
# up{job="payment", pod="payment-xxx"...} 1   ← 1=스크레이프 성공
# Pod 하나를 죽이면:
kubectl -n shop delete pod -l app=payment --wait=false
sleep 20
curl -s 'localhost:9090/api/v1/query?query=up{namespace="shop"}==0' | head -c 300
# 죽는 순간의 타깃이 0으로 — "타깃 다운" 알림의 원천
```

## 5. 정리

```bash
kill %1 2>/dev/null || true
# 클러스터·스택은 lab-02에서 계속
```

## 정리

- 스택 하나로 Operator·서버·3대장·기본 수집이 가동 — 컨트롤 플레인까지 이미 긁는 중
- ServiceMonitor = 선언형 등록: 중앙 설정 없이 앱 팀 셀프서비스
- **매칭 3연쇄**(release 라벨·Service 라벨·포트 이름) — 하나 어긋나면 조용한 미수집
- up == 0 / absent()가 타깃 생사·미수집의 감지 수단 (10의 알림 재료)
- **★ "안 보이는 실패(미수집)를 보이게 만드는 것"까지가 수집 체계입니다**
