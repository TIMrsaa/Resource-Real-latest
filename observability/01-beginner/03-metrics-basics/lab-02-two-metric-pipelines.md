# Lab 02 — 두 메트릭 파이프라인: metrics-server와 모니터링의 분리

> metrics-server를 설치해 리소스 메트릭 파이프라인(kubectl top·HPA용)을 살리고, 같은 컨테이너의 CPU를 ① Metrics API ② cAdvisor 원본 두 경로로 읽어 "왜 숫자가 다른가"를 원리로 이해합니다.

## 0. 준비 (lab-01 클러스터 이어서)

```bash
kubectl top nodes
# error: Metrics API not available   ← 아직 파이프라인이 없습니다 (01에서 봤던 것)
```

## 1. metrics-server 설치

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# kind는 kubelet 인증서가 자체 서명이라 TLS 예외 필요 (kind 한정 설정)
kubectl patch deploy metrics-server -n kube-system --type=json -p \
  '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl rollout status deploy/metrics-server -n kube-system --timeout=120s
```

```bash
# Metrics API가 생겼습니다 (Aggregated API)
kubectl get apiservices | grep metrics
# v1beta1.metrics.k8s.io   kube-system/metrics-server   True

sleep 30   # 첫 수집 대기
kubectl top nodes
# NAME                    CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# metrics-control-plane   180m         4%     720Mi           18%
```

**구조 확인** — 경로: cAdvisor(kubelet) → metrics-server가 주기 수집 → `metrics.k8s.io` API로 노출 → kubectl top·HPA가 조회. metrics-server는 **저장하지 않습니다**(최신 스냅샷만) — 이력이 필요하면 이 파이프라인이 아닙니다.

## 2. 부하 걸고 두 경로로 읽기

```bash
# CPU를 쓰는 Pod
kubectl run burner --image=busybox --restart=Never -- \
  sh -c 'while true; do :; done'    # busy loop (1코어 근처)
sleep 60
```

### 경로 ① Metrics API (kubectl top)

```bash
kubectl top pod burner
# NAME     CPU(cores)   MEMORY(bytes)
# burner   999m         0Mi
# → metrics-server의 창(수집 주기 기반 평균) 스냅샷
```

### 경로 ② cAdvisor 원본 (counter!)

```bash
NODE=$(kubectl get pod burner -o jsonpath='{.spec.nodeName}')
kubectl get --raw /api/v1/nodes/$NODE/proxy/metrics/cadvisor \
  | grep 'container_cpu_usage_seconds_total{container="burner"' 
# container_cpu_usage_seconds_total{container="burner",...} 58.3
# ← 누적 CPU 초! (counter) — 지금 몇 코어 쓰는지가 아님

# 30초 뒤 다시
sleep 30
kubectl get --raw /api/v1/nodes/$NODE/proxy/metrics/cadvisor \
  | grep 'container_cpu_usage_seconds_total{container="burner"'
# ... 88.1
```

**손 계산** — (88.1-58.3)/30s = **0.993 코어** ≈ top의 999m. 두 경로가 같은 원천(cAdvisor)을 다르게 가공합니다:

```
Metrics API: metrics-server가 미리 창 평균을 계산해 "지금 값"으로 제공
Prometheus: counter 원본을 저장하고, 조회 시 rate()로 아무 창이나 계산

kubectl top ≈ rate(container_cpu_usage_seconds_total[창])
→ 창·시점이 다르면 숫자가 다르다 = "top ≠ Grafana"의 정체
```

## 3. HPA가 이 파이프라인을 씁니다 (연결 확인)

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: scale-me
  labels: { app: scale-me }
spec:
  replicas: 1
  selector:
    matchLabels: { app: scale-me }
  template:
    metadata:
      labels: { app: scale-me }
    spec:
      containers:
        - name: nginx
          image: nginx
          resources:
            requests: { cpu: 100m }    # HPA %의 분모 — 없으면 <unknown>
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: scale-me
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: scale-me
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
EOF

kubectl get hpa scale-me
# TARGETS: 0%/50%   ← 이 0%가 Metrics API에서 옵니다!
# metrics-server가 죽으면 → TARGETS: <unknown> → HPA 마비
```

**핵심** — HPA(k8s 파트의 그것)의 눈이 바로 이 파이프라인입니다. metrics-server 장애 = 오토스케일 장애. "관측 컴포넌트"처럼 보이는 것이 실은 **플랫폼의 반사신경**입니다. (커스텀 메트릭 스케일은 prometheus-adapter나 KEDA(cncf 18)로 — 두 세계의 접점.)

## 4. 두 파이프라인 총정리 (그리기)

```
                   [cAdvisor (kubelet 내장)]
                     │                 │
        ┌────────────┘                 └──────────────┐
        ▼ (주기 수집, 최신만)                          ▼ (scrape, 저장)
  [metrics-server]                             [Prometheus (08)]
        ▼ Metrics API                                  ▼ TSDB·PromQL
  kubectl top / HPA / VPA                    Grafana(09)·알림(10)·조사
  "지금" — 플랫폼 반사신경                     "추세·이력" — 사람의 눈

같은 원천, 다른 목적, 다른 가공 → 숫자가 달라도 정상
```

## 5. 정리

```bash
kubectl delete hpa scale-me; kubectl delete deploy scale-me
kubectl delete pod burner --force --grace-period=0
kind delete cluster --name metrics
```

## 정리

- metrics-server: cAdvisor → Metrics API — **저장 없는 스냅샷**, kubectl top·HPA 전용
- cAdvisor 원본은 counter(누적 CPU 초) — top의 값 = 그것의 창 평균(rate)
- 손 계산으로 검증: (88.1-58.3)/30 ≈ 999m — 두 경로는 같은 원천의 다른 가공
- HPA의 눈 = 이 파이프라인 — metrics-server 장애는 오토스케일 장애
- **★ "top ≠ Grafana"는 버그가 아닙니다 — 파이프라인·창·시점이 다른 정상적 차이**
