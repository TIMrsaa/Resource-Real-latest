# Lab 01 — 2층 파이프라인: Bit → Fluentd forward

> 노드층(Fluent Bit)과 집계층(Fluentd)을 연결합니다. forward 프로토콜, ack 신뢰성, 그리고 "집계층이 죽으면 노드층이 어떻게 버티나"(06의 버퍼가 여기서 다시)를 확인합니다.

## 0. 준비

```bash
kind create cluster --name twotier
kubectl create namespace logging

# 로그 발생기
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: talker
  labels: { app: talker }
spec:
  replicas: 1
  selector:
    matchLabels: { app: talker }
  template:
    metadata:
      labels: { app: talker }
    spec:
      containers:
        - name: talker
          image: busybox
          command:
            - sh
            - -c
            - |
              i=0; while true; do i=$((i+1)); echo "{\"seq\":$i,\"card\":\"1234-5678-9012-3456\",\"msg\":\"order placed\"}"; sleep 0.5; done
EOF
```

(레코드에 카드번호를 넣어 뒀습니다 — lab-02 마스킹의 재료입니다.)

## 1. 집계층 — Fluentd Deployment

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: fluentd-config, namespace: logging }
data:
  fluent.conf: |
    <source>
      @type forward
      port 24224
      bind 0.0.0.0
    </source>

    # 집계층 표식 추가 (멀티클러스터 대비 — 어느 클러스터에서 왔나)
    <filter kube.**>
      @type record_transformer
      <record>
        cluster kind-twotier
        tier aggregated
      </record>
    </filter>

    # 일단 stdout으로 (목적지는 lab-02·12·13·18에서)
    <match kube.**>
      @type stdout
    </match>
    <match **>
      @type stdout
    </match>
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: fluentd, namespace: logging }
spec:
  replicas: 2                       # ★ 집계층도 가용성 (단일점 금지)
  selector: { matchLabels: { app: fluentd } }
  template:
    metadata: { labels: { app: fluentd } }
    spec:
      containers:
        - name: fluentd
          image: fluent/fluentd:v1.17-1
          ports: [{ containerPort: 24224 }]
          volumeMounts: [{ name: cfg, mountPath: /fluentd/etc }]
      volumes: [{ name: cfg, configMap: { name: fluentd-config } }]
---
apiVersion: v1
kind: Service
metadata: { name: fluentd, namespace: logging }
spec:
  selector: { app: fluentd }
  ports: [{ port: 24224 }]
EOF
kubectl -n logging rollout status deploy/fluentd --timeout=120s
```

## 2. 노드층 — Bit의 출력을 forward로

```bash
helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null; helm repo update

cat > /tmp/fb-forward.yaml <<'EOF'
config:
  service: |
    [SERVICE]
        Flush         1
        HTTP_Server   On
        HTTP_Port     2020
        storage.path  /var/log/flb-storage/
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Tag               kube.*
        multiline.parser  cri
        DB                /var/log/flb_kube.db
        storage.type      filesystem
  filters: |
    [FILTER]
        Name              kubernetes
        Match             kube.*
        Merge_Log         On
        Keep_Log          Off
  outputs: |
    [OUTPUT]
        Name                    forward
        Match                   kube.*
        Host                    fluentd.logging.svc.cluster.local
        Port                    24224
        Require_ack_response    True        # ★ ack 신뢰성
        storage.total_limit_size 200M
EOF
helm install fluent-bit fluent/fluent-bit -n logging -f /tmp/fb-forward.yaml
kubectl -n logging rollout status ds/fluent-bit --timeout=120s
```

## 3. 2층 흐름 검증

```bash
sleep 10
# 집계층에서 레코드 확인 — 노드층 메타데이터 + 집계층 표식이 함께
kubectl -n logging logs deploy/fluentd | grep '"seq"' | tail -1 | head -c 500
# kube.var.log...: {"seq":42,"card":"1234-5678-9012-3456","msg":"order placed",
#   "kubernetes":{"pod_name":"talker-...","namespace_name":"default",...},   ← 노드층(Bit)이 붙임
#   "cluster":"kind-twotier","tier":"aggregated"}                            ← 집계층(D)이 붙임
```

**관찰** — 한 레코드에 두 층의 손길이 겹칩니다: Bit이 CRI 파싱+JSON 승격+k8s 메타데이터(06), Fluentd가 클러스터 표식(멀티클러스터의 준비, 24). 분업이 실제로 돌고 있습니다.

## 4. 집계층 장애 — 노드층 버퍼가 받칩니다

```bash
# 집계층 전멸
kubectl -n logging scale deploy/fluentd --replicas=0
sleep 45

# 노드층: forward 재시도 + fs 버퍼 적재 (06 lab-02의 방어가 여기서 작동)
kubectl -n logging port-forward ds/fluent-bit 2020:2020 &
sleep 2
curl -s localhost:2020/api/v1/metrics/prometheus | grep -E "retries_total|dropped"
# retries_total 증가 중, dropped 0 (fs 버퍼 덕)
kill %1

# 집계층 부활 → 밀린 로그 배달
kubectl -n logging scale deploy/fluentd --replicas=2
kubectl -n logging rollout status deploy/fluentd --timeout=120s
sleep 30
kubectl -n logging logs deploy/fluentd --since=30s | grep -c '"seq"'
# 부활 직후 급증 — 밀린 seq들이 몰려옴 (구멍 없이)
```

**핵심** — 집계층 다운이 유실로 이어지지 않았습니다: 노드층 fs 버퍼(06) + forward 재시도가 받쳤습니다. **2층의 신뢰성 = 각 구간의 버퍼 × ack** — 한 구간이라도 mem 버퍼+ack 없음이면 그 구간이 유실 지점이 됩니다. seq 번호로 구멍 없음을 확인하는 습관(유실의 물증 검증)도 기억하세요.

## 5. ack의 값 확인 (개념)

```
Require_ack_response True의 의미 재확인:
  Bit: chunk 전송 → Fluentd의 "버퍼에 기록했음" 응답까지 대기
  → Fluentd가 받자마자 죽어도(기록 전) Bit은 미확인으로 재전송
  → 유실 창이 "TCP 전송 후"에서 "버퍼 기록 후"로 축소

대가: 왕복 대기만큼 처리량 하락 — 대량 저가치 로그에는 과할 수 있음
등급별 판단(06): 감사·결제 = ack, 대량 debug = ack 없이 (또는 애초 필터)
```

## 6. 정리

```bash
# 클러스터는 lab-02에서 계속
echo "집계층 가공(마스킹·copy)은 lab-02에서"
```

## 정리

- 2층 연결: Bit(tail·CRI·k8s 메타) → forward(ack) → Fluentd(표식·가공) — 분업 확인
- 집계층 다운을 노드층 fs 버퍼+재시도가 흡수 — **구간마다 버퍼×ack가 신뢰성**
- 집계층도 replicas 2+ (가용성) — 단일 애그리게이터는 전 노드의 단일 장애점
- ack는 유실 창을 줄이는 대신 처리량 대가 — 로그 등급별로
- **★ 2층의 신뢰성은 가장 약한 구간이 정합니다 (04의 "가장 약한 고리"가 파이프라인에도)**
