# Lab 01 — ADOT 애드온·IRSA·분배 파이프라인

> ADOT를 EKS 애드온으로 설치하고, IRSA(3정책)를 배선하고, "수집 한 번 → AMP+X-Ray 분배" 파이프라인을 구성해 11의 앱이 그대로 AWS 백엔드에 신호를 흘리게 합니다.

## ⚠️ 비용 주의

AMP 샘플·X-Ray 트레이스(수집 100만 건당 과금)·CW 발생. cleanup.sh 필수.

## 0. 준비

```bash
export CLUSTER=my-eks REGION=ap-northeast-2
# 14의 AMP 워크스페이스 재사용 (없으면 lab-01 방식으로 생성)
export WS_ID=<ws-id>
export AMP_ENDPOINT=$(aws amp describe-workspace --region $REGION \
  --workspace-id $WS_ID --query 'workspace.prometheusEndpoint' --output text)

# cert-manager (Operator 전제 — 11과 동일)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager wait deploy --all --for=condition=Available --timeout=180s
```

## 1. IRSA — 세 정책의 허가증

```bash
kubectl create namespace observability 2>/dev/null || true
eksctl create iamserviceaccount \
  --cluster $CLUSTER --region $REGION \
  --namespace observability --name adot-collector \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess \
  --attach-policy-arn arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess \
  --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
  --approve
```

## 2. ADOT 애드온 설치

```bash
aws eks create-addon --cluster-name $CLUSTER --region $REGION --addon-name adot
sleep 60
kubectl get pods -n opentelemetry-operator-system
# opentelemetry-operator-... Running   ← 11의 Operator가 애드온으로
```

## 3. 분배 Collector — 이 모듈의 본체

```bash
cat <<EOF | kubectl apply -f -
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata: { name: adot, namespace: observability }
spec:
  mode: deployment
  serviceAccount: adot-collector          # ★ IRSA
  config:
    receivers:
      otlp: { protocols: { grpc: {}, http: {} } }
    processors:
      memory_limiter: { check_interval: 1s, limit_percentage: 75, spike_limit_percentage: 20 }
      k8sattributes: {}
      batch: {}
    exporters:
      awsxray:
        region: $REGION
      prometheusremotewrite:
        endpoint: ${AMP_ENDPOINT}api/v1/remote_write
        auth: { authenticator: sigv4auth }
    extensions:
      sigv4auth: { region: $REGION, service: aps }
    service:
      extensions: [sigv4auth]
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, batch]
          exporters: [awsxray]
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [prometheusremotewrite]
EOF
kubectl -n observability rollout status deploy/adot-collector --timeout=180s
```

**읽기** — 11 lab-02의 gateway와 같은 뼈대에 exporter만 AWS로: traces→awsxray, metrics→prometheusremotewrite(sigv4auth extension). 설정이 낯익다는 것 자체가 "ADOT = 아는 도구"의 증명입니다.

## 4. 11의 앱을 그대로 — 계측 재사용

```bash
kubectl create namespace shop 2>/dev/null || true
# Instrumentation은 11과 동일, endpoint만 ADOT로
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata: { name: default, namespace: shop }
spec:
  exporter: { endpoint: http://adot-collector.observability:4318 }
  propagators: [tracecontext]
  sampler: { type: parentbased_traceidratio, argument: "1.0" }
  python:
    env: [{ name: OTEL_EXPORTER_OTLP_PROTOCOL, value: http/protobuf }]
EOF
# 11 lab-01의 app-a/app-b(주문→재고)를 그대로 배포 (생략 — 같은 매니페스트)
# kubectl apply -f <11의 app-a, app-b 매니페스트>
```

(11의 A→B 앱 매니페스트를 그대로 적용합니다 — 계측·어노테이션 변경 없음. **앱 관점에서 백엔드 교체는 무형**입니다.)

```bash
# 트래픽
kubectl -n shop run traffic --image=curlimages/curl --restart=Never -- sh -c '
  for i in $(seq 1 30); do curl -s http://app-a:8080/order >/dev/null; sleep 1; done'
sleep 90
```

## 5. 양쪽 백엔드 검증

```bash
# ① AMP에 메트릭 도착? (자동 계측의 HTTP 메트릭)
awscurl --service aps --region $REGION \
  "${AMP_ENDPOINT}api/v1/query?query=http_server_duration_milliseconds_count" | head -c 300
# 결과 있음 → 메트릭 분배 성공

# ② X-Ray에 트레이스 도착?
aws xray get-trace-summaries --region $REGION \
  --start-time $(date -d '-10 minutes' +%s) --end-time $(date +%s) \
  --query 'TraceSummaries[0].{id:Id,duration:Duration}' 
# trace ID가 나옴 → 트레이스 분배 성공! (상세 조사는 17에서)

# ③ AMG(15)에서: X-Ray 데이터소스 Explore → 트레이스가 이제 보입니다
#    (15에서 "자리만" 잡았던 것이 채워짐)
```

**확인의 의미** — 앱은 OTLP 한 번만 내보냈는데(11의 계측 그대로), 메트릭은 AMP에, 트레이스는 X-Ray에 도착했습니다. "수집 한 번, 목적지 셋"의 실증 — Collector가 완충재라는 11의 설계가 AWS 세계에서 그대로 보상됐습니다.

## 6. 정리

```bash
# 리소스는 lab-02에서 계속
echo "EMF·판단은 lab-02에서"
```

## 정리

- IRSA 3정책(AMP·X-Ray·CW) 하나의 SA — AWS 관측 수집기의 허가증 세트
- ADOT 애드온 = Operator 방식 — 11의 CRD 문법 그대로
- 분배 파이프라인: traces→awsxray, metrics→prometheusremotewrite(sigv4auth)
- 11의 앱·계측 무변경 — 백엔드 교체가 앱에 무형 (Collector 완충재의 보상)
- **★ "수집 한 번, 목적지 셋" — AWS 관측 스택의 수집층이 완성됐습니다**
