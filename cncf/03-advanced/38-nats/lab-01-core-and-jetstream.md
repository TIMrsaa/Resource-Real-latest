# Lab 01 — 두 모드: core pub/sub와 JetStream 스트림

09 lab-02에서 만진 core와 JetStream을 이제 구조로 확인합니다 — subject·큐 그룹·request-reply·영속 스트림.

전제: kind, kubectl, helm.

## Step 1. 클러스터와 NATS (JetStream 활성)

```bash
kind create cluster --name nats -q

helm repo add nats https://nats-io.github.io/k8s/helm/charts >/dev/null 2>&1
helm install nats nats/nats -n nats --create-namespace \
  --set config.jetstream.enabled=true >/dev/null
kubectl -n nats rollout status statefulset/nats --timeout=180s

kubectl -n nats run box --image=natsio/nats-box:latest --restart=Never -- sleep 3600
kubectl -n nats wait --for=condition=ready pod/box --timeout=120s
N() { kubectl -n nats exec box -- "$@"; }
```

## Step 2. core NATS — subject와 fire-and-forget

```bash
echo "=== 계층적 subject + fire-and-forget ==="
N sh -c '
  # 구독자를 백그라운드로
  nats sub -s nats://nats:4222 "orders.*" --count=2 &
  sleep 1
  # 발행
  nats pub -s nats://nats:4222 orders.new "{\"id\":1}"
  nats pub -s nats://nats:4222 orders.paid "{\"id\":1}"
  sleep 2
  echo "--- 구독자 없이 발행 (유실) ---"
  nats pub -s nats://nats:4222 orders.new "{\"id\":2}"
  echo "--- 나중에 구독해도 id:2는 없습니다 (fire-and-forget) ---"
'
```

예상: orders.* 구독자가 new·paid를 받고, 구독자 없이 발행한 id:2는 유실. ✅ **core는 저장 안 함, 계층적 subject로 라우팅**(theory §1).

## Step 3. 큐 그룹 — 로드밸런싱

```bash
N sh -c '
  # 같은 큐 그룹 WORKERS의 워커 2개
  nats sub -s nats://nats:4222 tasks --queue WORKERS --count=5 &
  nats sub -s nats://nats:4222 tasks --queue WORKERS --count=5 &
  sleep 1
  # 10개 발행 → 두 워커가 나눠 받음
  for i in $(seq 1 10); do nats pub -s nats://nats:4222 tasks "task-$i"; done
  sleep 2
'
echo "→ 같은 큐 그룹의 워커들이 메시지를 나눠 받음 (로드밸런싱 — theory §1)"
echo "  일반 pub/sub은 모두 받지만(팬아웃), 큐 그룹은 하나만(작업 분배)"
```

## Step 4. request-reply — 양방향

```bash
N sh -c '
  # 응답자 (서비스)
  nats reply -s nats://nats:4222 "service.echo" "reply: {{Request}}" &
  sleep 1
  # 요청자
  nats request -s nats://nats:4222 "service.echo" "hello"
  sleep 1
'
echo "→ pub/sub 기반 요청-응답 (theory §2)"
echo "  마이크로서비스 RPC를 메시징으로 (24의 service invocation과 계열)"
echo "  응답자를 큐 그룹으로 하면 로드밸런싱된 RPC"
```

## Step 5. ★ JetStream — 영속 스트림 (재생 가능)

```bash
N sh -c '
  # 스트림 생성 (orders.* 를 저장)
  nats -s nats://nats:4222 stream add ORDERS \
    --subjects "orders.*" --storage file --retention limits \
    --max-msgs 1000 --max-bytes -1 --max-age 24h --discard old \
    --dupe-window 2m --replicas 1 --no-allow-rollup --no-deny-delete --no-deny-purge >/dev/null 2>&1

  echo "--- 구독자 없이 발행 ---"
  nats -s nats://nats:4222 pub orders.new "{\"id\":10}"
  nats -s nats://nats:4222 pub orders.new "{\"id\":11}"

  echo "--- 나중에 처음부터 재생 (core는 유실됐지만 JetStream은 저장) ---"
  nats -s nats://nats:4222 sub orders.new --all --count=2 2>/dev/null | grep -i "id" | head -4
'
```

예상: 나중에 붙은 구독자가 id:10·11을 재생. ✅ **JetStream은 저장·재생**(theory §3) — 같은 NATS인데 core(유실)와 정반대. 09의 "나중에 다시 읽어야 하는가"의 답.

## Step 6. Stream과 Consumer — Kafka 유사 모델

```bash
N sh -c '
  echo "=== 스트림 정보 ==="
  nats -s nats://nats:4222 stream info ORDERS 2>/dev/null | grep -E "Messages|Bytes|Storage" | head -3

  echo "=== Consumer (읽기 위치·ack) ==="
  nats -s nats://nats:4222 consumer add ORDERS PROCESSOR \
    --pull --deliver all --ack explicit --max-deliver 3 --wait 5s \
    --replay instant --filter "" --no-headers-only --backoff none 2>/dev/null >/dev/null || true
  nats -s nats://nats:4222 consumer info ORDERS PROCESSOR 2>/dev/null | grep -E "Delivery|Ack" | head -3
'

cat <<'EOF'

JetStream 모델 (theory §3, Kafka 유사):
  Stream ≈ Kafka 토픽 (영속 로그)
  Consumer ≈ Kafka 컨슈머 그룹
    push/pull, 위치(all/last/시퀀스), ack(at-least-once)
  → 재생·여러 컨슈머·감사 (스트림의 특성)
EOF
```

## Step 7. 산출물

```markdown
# NATS 두 모드 카드
## core NATS (큐)
- fire-and-forget, 저장 안 함, 구독자 없으면 유실
- subject 계층(orders.*), 큐 그룹(로드밸런싱), request-reply
- 초경량·저지연, 실시간 통신

## JetStream (스트림)
- 영속 저장, 재생 가능, at-least-once (ack)
- Stream(≈Kafka 토픽) + Consumer(≈컨슈머 그룹)
- 이벤트 소싱·재처리·감사

## 판단 (09)
- "나중에 다시 읽어야?" → JetStream / "지금 안 들으면 그만" → core
```

## 정리

lab-02에서 패턴·클러스터링·선택을 다룹니다. 유지.
