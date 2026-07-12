# Lab 02 — Collector 3패턴과 파이프라인·샘플링

> agent(DaemonSet)→gateway(Deployment)의 2층 Collector를 구축하고, k8sattributes·memory_limiter·tail 샘플링을 배치합니다. 06→07의 로그 2층과 같은 그림이 트레이스에서 재현되는 것을 확인합니다.

## 0. 준비 (lab-01 이어서)

## 1. gateway — 중앙 정책층 (tail 샘플링의 자리)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata: { name: gateway, namespace: observability }
spec:
  mode: deployment
  replicas: 2                                  # 07의 교훈 — 정책층도 HA
  config:
    receivers:
      otlp: { protocols: { grpc: {}, http: {} } }
    processors:
      memory_limiter:                          # ★ 자기 보호 첫 번째 (06 사상)
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 20
      tail_sampling:                           # ★ tail — 전 span이 모이는 곳에서만
        decision_wait: 10s
        policies:
          - name: errors-always
            type: status_code
            status_code: { status_codes: [ERROR] }     # 에러 trace 100%
          - name: slow-always
            type: latency
            latency: { threshold_ms: 500 }             # 느린 trace 100%
          - name: baseline
            type: probabilistic
            probabilistic: { sampling_percentage: 10 } # 나머지 10%
      batch: {}
    exporters:
      debug: { verbosity: normal }             # 실전: otlp/tempo·awsxray(16·17)
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, tail_sampling, batch]
          exporters: [debug]
EOF
kubectl -n observability rollout status deploy/gateway-collector --timeout=120s
```

## 2. agent — 노드 수집층

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata: { name: agent, namespace: observability }
spec:
  mode: daemonset                              # ★ 노드마다 (06의 DS와 같은 이유)
  config:
    receivers:
      otlp: { protocols: { grpc: {}, http: {} } }
    processors:
      memory_limiter: { check_interval: 1s, limit_percentage: 70, spike_limit_percentage: 20 }
      k8sattributes: {}                        # ★ k8s 메타 부착 — 노드 로컬에서 (06 kubernetes 필터 사상)
      batch: {}
    exporters:
      otlp/gateway:
        endpoint: gateway-collector.observability:4317
        tls: { insecure: true }
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, batch]
          exporters: [otlp/gateway]
EOF
kubectl -n observability rollout status ds/agent-collector --timeout=120s

# 앱의 목적지를 agent로 변경 (Instrumentation 수정)
kubectl -n shop patch instrumentation default --type merge -p '
spec:
  exporter: { endpoint: http://agent-collector.observability:4318 }
'
kubectl -n shop rollout restart deploy/app-a deploy/app-b
kubectl -n shop rollout status deploy/app-a deploy/app-b --timeout=300s
```

**구조 확인** — `앱 → agent(DS, k8s 메타) → gateway(정책·tail 샘플링) → 백엔드`. 06(Bit)→07(Fluentd)과 완전히 같은 그림입니다 — 수집기의 사상은 하나입니다.

## 3. tail 샘플링 검증 — 에러·느림은 남고, 평범한 것은 걸러집니다

```bash
# 트래픽: 정상 다수 (전부 빠름·성공 — baseline 10%만 남아야)
kubectl -n shop run traffic --image=curlimages/curl --restart=Never -- sh -c '
  for i in $(seq 1 50); do curl -s http://app-a:8080/order >/dev/null; sleep 0.3; done'
sleep 60

# gateway가 내보낸 trace 수 세기 (10% 근처여야)
kubectl -n observability logs deploy/gateway-collector --since=2m | grep -c "GET /order" 
# ~5 (50건 중 10%±) ← 평범한 trace는 걸러짐

# B를 느리게 만들면? (threshold 500ms 초과 유발)
kubectl -n shop patch configmap app-b-code --type merge -p '{"data":{"app.py":"from flask import Flask\nimport time\napp = Flask(__name__)\n@app.route(\"/stock\")\ndef stock():\n    time.sleep(0.8)\n    return {\"stock\": 42}\napp.run(host=\"0.0.0.0\", port=8080)\n"}}'
kubectl -n shop rollout restart deploy/app-b
kubectl -n shop rollout status deploy/app-b --timeout=300s

kubectl -n shop run traffic2 --image=curlimages/curl --restart=Never -- sh -c '
  for i in $(seq 1 20); do curl -s http://app-a:8080/order >/dev/null; sleep 0.3; done'
sleep 60
kubectl -n observability logs deploy/gateway-collector --since=2m | grep -c "GET /order"
# ~20 — ★ 느린 trace(>500ms)는 100% 보존! (slow-always 정책)
```

**의미** — tail 샘플링이 "재미있는 것"(에러·느림)을 골라 남겼습니다: 평시 볼륨은 10%로 통제하면서 조사에 필요한 사례는 전량 보존 — head만으로는 불가능한 선별(04)입니다. decision_wait(10s) 동안 trace를 버퍼하는 메모리 비용이 대가이고, 그래서 이 processor는 span이 모이는 gateway에만 있습니다.

## 4. k8sattributes 검증 — 메타데이터의 자동 부착

```bash
kubectl -n observability logs deploy/gateway-collector --since=5m | grep -B2 -A8 "k8s.pod.name" | head -15
# Attributes: k8s.pod.name: app-a-..., k8s.namespace.name: shop,
#             k8s.deployment.name: app-a ...
# ← agent의 k8sattributes가 붙임 — "어느 Pod의 span인가"가 데이터로
#   (06의 kubernetes 필터가 로그에 한 일의 트레이스판)
```

## 5. 3패턴 판단 정리

```
이 실습의 구성이 표준 조합인 이유:
  agent(DS): 앱이 가까운 곳(노드)에 던짐 — 홉 최소, k8s 메타는 로컬에서
  gateway: tail 샘플링(span 집결 필요)·백엔드 인증·라우팅 집중
  sidecar는 안 씀: 강한 격리 요구가 없으므로 (리소스 낭비)

축소판: 소규모면 agent 단독 → 백엔드 직행 (gateway 생략 — 07의 판단)
확장판: gateway 앞에 trace_id 기반 loadbalancing exporter (tail의 전제)
```

## 6. SIGNALS-MAP 갱신 (과제)

```
트레이스 줄 갱신:
  계측: OTel Operator 자동 주입 (Python/Java — 어노테이션)
  수집: agent(DS, k8sattributes) → gateway(tail 샘플링)
  샘플링: head 100%(실습) + tail(에러·느림 100%, 기본 10%)
  백엔드: debug(→ 12에서 Tempo, 17에서 X-Ray)
  상태: 🔶 (백엔드 남음)
```

## 7. 정리

```bash
kind delete cluster --name otel
```

## 정리

- agent(DS)→gateway 2층 = 로그의 06→07과 동형 — **수집기의 사상은 하나**
- memory_limiter는 모든 Collector의 첫 processor (자기 보호)
- tail 샘플링은 gateway에서만 — span 집결·버퍼 비용, 에러·느림 100% 보존 검증
- k8sattributes = 로그의 kubernetes 필터 — 신호마다 같은 요구(어느 Pod인가)
- **★ head로 볼륨을 통제하고 tail로 사례를 선별 — "개수는 메트릭, 사례는 트레이스"의 구현**
