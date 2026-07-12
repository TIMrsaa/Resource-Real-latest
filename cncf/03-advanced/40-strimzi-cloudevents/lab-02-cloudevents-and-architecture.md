# Lab 02 — CloudEvents 표준과 이벤트 기반 아키텍처

> CloudEvents 봉투 형식을 실제로 만들어 보고, 여러 소스가 하나의 형식으로 통일되는 것을 확인하고, Strimzi(40)·NATS(38)·Dapr(29)·KEDA(18)·Knative가 이벤트 아키텍처에서 어떻게 조합되는지를 개념·미니 실습으로 익힙니다.

## 1. CloudEvents 봉투 — 직접 만들어 보기

CloudEvents는 코드가 아니라 형식입니다. HTTP로 이벤트를 보낼 때의 두 바인딩을 봅니다.

### 구조화(structured) — 봉투 전체가 JSON body

```bash
# CloudEvent 하나 (structured 모드): 봉투가 통째로 body
cat > event.json <<'EOF'
{
  "specversion": "1.0",
  "type": "com.example.order.created",
  "source": "/orders/checkout-service",
  "id": "0a1b2c3d-1111-2222-3333-444455556666",
  "time": "2026-07-11T12:00:00Z",
  "datacontenttype": "application/json",
  "subject": "order/123",
  "data": { "orderId": 123, "amount": 42000, "currency": "KRW" }
}
EOF

# 어떤 HTTP 수신자에게 보내든 Content-Type으로 구분
# Content-Type: application/cloudevents+json
```

### 이진(binary) — 컨텍스트는 헤더, data만 body

```bash
# 같은 이벤트, binary 모드: 컨텍스트 속성이 HTTP 헤더로
# ce-specversion: 1.0
# ce-type: com.example.order.created
# ce-source: /orders/checkout-service
# ce-id: 0a1b2c3d-...
# ce-time: 2026-07-11T12:00:00Z
# Content-Type: application/json
# (body)
# { "orderId": 123, "amount": 42000, "currency": "KRW" }
```

**핵심** — 같은 이벤트를 두 방식으로 전송할 수 있습니다. 수신자는 `ce-*` 헤더나 `application/cloudevents+json`을 보고 CloudEvent임을 압니다. `data`만 앱마다 다르고, **봉투(specversion·type·source·id)는 항상 같습니다** — 이것이 통일의 핵심입니다.

## 2. 여러 소스를 하나의 형식으로 (통일 확인)

```
같은 이벤트를 세 소스가 CloudEvents로 표현하면 소비자는 하나의 코드로 처리:

S3 오브젝트 생성 →
  { specversion, type: "com.amazonaws.s3.ObjectCreated", source: "aws:s3:...", data: {...} }

Kafka(40) orders 토픽 메시지 →
  { specversion, type: "com.example.order.created", source: "/orders/...", data: {...} }

NATS(38) 메시지 →
  { specversion, type: "com.example.sensor.reading", source: "/sensors/...", data: {...} }

소비자 코드(의사):
  def handle(event):        # event는 항상 CloudEvent
    if event.type == "com.example.order.created":
      process_order(event.data)
    # source가 S3든 Kafka든 NATS든 파싱 코드는 동일
```

이것이 06(OTel)·03(OCI)과 같은 계열의 가치입니다 — **형식이 통일되면 소스가 바뀌어도 소비자를 안 바꿉니다**(이식성).

## 3. 미니 실습 — CloudEvents 수신 서버

```bash
kubectl create namespace events

# CloudEvent를 받아 로그로 찍는 간단한 수신자 (표준 sockeye 또는 event-display)
cat <<'EOF' | kubectl apply -n events -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-display
spec:
  replicas: 1
  selector: { matchLabels: { app: event-display } }
  template:
    metadata: { labels: { app: event-display } }
    spec:
      containers:
        - name: display
          image: gcr.io/knative-releases/knative.dev/eventing/cmd/event_display
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata:
  name: event-display
spec:
  selector: { app: event-display }
  ports: [{ port: 80, targetPort: 8080 }]
EOF

kubectl -n events wait deploy/event-display --for=condition=Available --timeout=120s
```

```bash
# CloudEvent 하나를 curl로 보내기 (binary 모드 헤더)
kubectl -n events run curl -ti --image=curlimages/curl --rm=true --restart=Never -- \
  curl -v http://event-display.events.svc.cluster.local \
    -H "Ce-Specversion: 1.0" \
    -H "Ce-Type: com.example.order.created" \
    -H "Ce-Source: /orders/checkout" \
    -H "Ce-Id: test-001" \
    -H "Content-Type: application/json" \
    -d '{"orderId": 123, "amount": 42000}'

# event-display 로그에서 파싱된 CloudEvent 확인
kubectl -n events logs -l app=event-display
# ☁️  cloudevents.Event
# Context Attributes,
#   specversion: 1.0
#   type: com.example.order.created
#   source: /orders/checkout
#   id: test-001
# Data,
#   {"orderId": 123, "amount": 42000}
```

**관찰** — 수신자가 `Ce-*` 헤더를 CloudEvent로 파싱했습니다. 회원님이 보낸 봉투 그대로 구조화되어 나옵니다. 이 수신자는 소스가 무엇이든(S3든 Kafka든) 같은 형식이면 같게 처리합니다.

## 4. 이벤트 기반 아키텍처 — 조합 지도

```
데이터 트랙의 부품들이 이벤트 아키텍처에서 만나는 방식:

  [이벤트 소스]  →  CloudEvents 형식(40)  →  [브로커]  →  [소비자]  →  [스케일]
   앱·S3·센서                              Kafka(40)/    Dapr(29)     KEDA(18)
                                          NATS(38)      pub/sub      lag→scale
                                          Knative
                                          Broker(15)

층별 역할:
  형식(40 CloudEvents): 이벤트의 공통 봉투
  전송(40 Kafka / 38 NATS): 영속 로그 vs 경량 실시간
  추상(29 Dapr): 앱은 pub/sub API만, 백엔드는 CloudEvents로 교체 가능
  라우팅(Knative Eventing): Broker + Trigger로 type별 라우팅
  스케일(18 KEDA): 미처리 이벤트(Kafka lag·NATS pending)로 소비자 오토스케일
```

### 조합 예시 — 주문 처리 파이프라인

```
1. checkout-service가 주문 → CloudEvent(order.created) 발행
2. Dapr(29) pub/sub이 CloudEvents로 감싸 Kafka(40)에 저장 (영속)
3. Knative Trigger가 type=order.created를 결제 서비스로 라우팅
4. Kafka lag이 쌓이면 KEDA(18)가 결제 워커를 스케일 (0→N)
5. 각 이벤트는 06(OTel) trace context를 CloudEvent extension으로 전파
   → 24의 분산 추적이 이벤트 흐름에도 적용
```

**24(메시)와의 대비** — 24는 동기 호출(A가 B를 호출하고 응답 대기)의 안정성을 다뤘습니다. 이벤트 기반은 **비동기·느슨한 결합**(A는 이벤트만 발행, B가 언제 처리하든 무관)입니다 — 같은 문제(서비스 간 통신)의 다른 패러다임이며, 실무는 둘을 섞습니다.

## 5. 정리

```bash
kubectl delete namespace events
```

## 정리

- CloudEvents는 이벤트의 **봉투 형식** — specversion·type·source·id는 항상 같고 data만 앱마다 다름
- 두 바인딩: structured(봉투 통째 body) / binary(컨텍스트는 `ce-*` 헤더)
- 여러 소스(S3·Kafka·NATS)를 하나의 형식으로 → 소비자는 소스 무관(06·03의 이식성)
- 이벤트 아키텍처 = 형식(CloudEvents) + 전송(Kafka/NATS) + 추상(Dapr) + 라우팅(Knative) + 스케일(KEDA)
- **★ 24의 동기 호출과 대비되는 비동기·느슨한 결합** — 실무는 둘을 조합
