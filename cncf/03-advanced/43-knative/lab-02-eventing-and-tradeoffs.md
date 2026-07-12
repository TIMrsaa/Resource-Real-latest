# Lab 02 — Knative Eventing과 서버리스 트레이드오프

> 40에서 배운 CloudEvents를 Knative Eventing(Broker·Trigger)으로 라우팅하고, 이벤트가 곧 스케일 트리거가 되는 이벤트 기반 서버리스를 구성합니다. 마지막으로 Knative vs KEDA vs HPA의 판단을 정리합니다.

## 0. 준비 (lab-01의 Knative + Eventing 설치 가정)

```bash
kubectl get pods -n knative-eventing
# eventing-controller, eventing-webhook ... Running
# (quickstart는 Eventing도 설치함)
```

## 1. Broker 생성 — 이벤트 버스

```bash
kubectl create namespace demo

# 기본 Broker (인메모리 채널 기반, 학습용)
cat <<'EOF' | kubectl apply -f -
apiVersion: eventing.knative.dev/v1
kind: Broker
metadata:
  name: default
  namespace: demo
EOF

kubectl -n demo get broker
# NAME      URL                                          READY
# default   http://broker-ingress.../demo/default        True
```

## 2. Sink — 이벤트 소비자 (Knative Service, scale-to-zero)

```yaml
# sink.yaml — 이벤트를 받는 서버리스 소비자 (40의 event-display)
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: event-display
  namespace: demo
spec:
  template:
    spec:
      containers:
        - image: gcr.io/knative-releases/knative.dev/eventing/cmd/event_display
```

```bash
kubectl apply -f sink.yaml
# event-display는 이벤트가 없으면 0으로 (scale-to-zero)
```

## 3. Trigger — 필터·라우팅 (CloudEvents type으로)

```yaml
# trigger.yaml — type=order.created 이벤트만 event-display로
apiVersion: eventing.knative.dev/v1
kind: Trigger
metadata:
  name: order-trigger
  namespace: demo
spec:
  broker: default
  filter:
    attributes:
      type: com.example.order.created   # 40의 CloudEvents type으로 필터
  subscriber:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: event-display
```

```bash
kubectl apply -f trigger.yaml
kubectl -n demo get trigger
# NAME            BROKER    SUBSCRIBER_URI   READY
# order-trigger   default   http://...       True
```

**구조** — `Source/발행자 → Broker → Trigger(filter: type) → Sink(Service)`. Trigger가 40에서 배운 CloudEvents의 `type` 속성으로 라우팅합니다.

## 4. 이벤트 발행 → 라우팅·스케일 관찰

```bash
# Broker에 CloudEvent 발행 (40의 binary 모드)
BROKER_URL=$(kubectl -n demo get broker default -o jsonpath='{.status.address.url}')

kubectl -n demo run curl -ti --image=curlimages/curl --rm=true --restart=Never -- \
  curl -v $BROKER_URL \
    -H "Ce-Specversion: 1.0" \
    -H "Ce-Type: com.example.order.created" \
    -H "Ce-Source: /orders/checkout" \
    -H "Ce-Id: order-001" \
    -H "Content-Type: application/json" \
    -d '{"orderId": 123}'

# event-display가 이벤트를 받으며 0→1로 뜹니다 (이벤트가 스케일 트리거)
kubectl -n demo get pod -l serving.knative.dev/service=event-display -w
# event-display-... 생성 (이벤트 도착으로 콜드 스타트)

kubectl -n demo logs -l serving.knative.dev/service=event-display
# ☁️  cloudevents.Event
#   type: com.example.order.created
#   source: /orders/checkout
#   id: order-001
# Data: {"orderId": 123}
```

**핵심** — 이벤트가 오자 소비자가 0→1로 떴고, 이벤트가 그치면 다시 0으로 갑니다. **이벤트가 곧 스케일 트리거**인 이벤트 기반 서버리스입니다. type 필터로 맞는 소비자에만 라우팅됐습니다(40의 CloudEvents 라우팅).

```bash
# 다른 type 이벤트는 이 Trigger가 무시 (필터 불일치)
kubectl -n demo run curl2 -ti --image=curlimages/curl --rm=true --restart=Never -- \
  curl -s $BROKER_URL -H "Ce-Specversion: 1.0" -H "Ce-Type: com.example.other" \
    -H "Ce-Source: /x" -H "Ce-Id: x-1" -H "Content-Type: application/json" -d '{}'
# → event-display 로그에 안 나타남 (type이 order.created가 아니므로)
```

## 5. 판단 정리 — Knative vs KEDA vs HPA

세 가지를 다 배웠으니(08 HPA, 18 KEDA, 43 Knative) 명확히 구분합니다:

```
시나리오별 선택:
  ① 상시 트래픽, CPU로 스케일          → HPA(08)
     (scale-to-zero 불필요, 가장 단순)
  ② 기존 Deployment를 이벤트로 0↔N     → KEDA(18)
     (Kafka lag·큐 길이로 워커 스케일, 가벼움)
  ③ 요청 기반 서버리스 + 카나리·트래픽  → Knative Serving(43)
     (scale-to-zero + 리비전 + 이식성)
  ④ 이벤트 라우팅 + 서버리스 소비       → Knative Eventing(43)
     (CloudEvents Broker·Trigger)

무게·복잡성 순: HPA < KEDA < Knative
→ 필요한 만큼만 (그냥 스케일에 Knative는 과함)

실무 조합:
  Knative Eventing으로 라우팅 + KEDA로 워커 스케일
  또는 Cloud Run(관리형 Knative)으로 운영 부담 없이
```

## 6. 트레이드오프 최종

```
Knative를 쓰는 값어치:
  + 드문 워크로드 비용 0 (scale-to-zero)
  + 이식성 (Lambda 종속 회피, Cloud Run 경로)
  + 카나리·트래픽·이벤트 라우팅 내장
비용:
  - 콜드 스타트 (지연 민감엔 부적합)
  - Activator·KPA·Eventing 운영 복잡성
  - 상시 트래픽엔 이점 없음

→ "서버리스가 정말 필요한가"를 먼저 (상시 트래픽이면 일반 Deployment)
```

## 7. 정리

```bash
kubectl delete namespace demo
```

## 정리

- Knative Eventing: Source→Broker→Trigger(filter)→Sink, 40의 CloudEvents로 라우팅
- Trigger가 CloudEvents `type`으로 소비자를 필터 → 이벤트가 곧 scale-to-zero 트리거
- 판단: HPA(상시·CPU) < KEDA(이벤트 스케일, 가벼움) < Knative(서버리스 플랫폼)
- 실무 조합: Knative Eventing 라우팅 + KEDA 스케일, 또는 Cloud Run(관리형)
- **★ "서버리스가 정말 필요한가"를 먼저 — 상시 트래픽이면 콜드 스타트만 손해**
