# Lab 02 — etcd의 watch·lease를 만지고, NATS로 큐와 스트림을 가릅니다

K8s API의 성질이 어디서 왔는지 etcd에서 직접 확인하고, 메시징의 두 모델을 같은 도구(NATS)로 대비합니다.

전제: kind, kubectl, helm.

## Step 1. 클러스터와 etcd 접근

```bash
kind create cluster --name data -q

# kind의 control-plane 안에 etcd가 static Pod로 있습니다
kubectl -n kube-system get pod -l component=etcd
docker exec data-control-plane sh -c 'ls /etc/kubernetes/pki/etcd/'
```

## Step 2. K8s가 etcd에 무엇을 쓰는지 봅니다

```bash
ETCDCTL='docker exec data-control-plane etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key'

eval "$ETCDCTL endpoint status --write-out=table"
eval "$ETCDCTL get /registry --prefix --keys-only" | head -10
```

예상: `/registry/pods/...`, `/registry/services/...` — **모든 K8s 오브젝트가 etcd의 키**입니다. ✅ "K8s의 상태는 etcd에 있다"가 문자 그대로임을 확인.

## Step 3. watch — 컨트롤러가 폴링하지 않는 이유

```bash
# 터미널 A 역할: watch를 백그라운드로 걸어둡니다
docker exec -d data-control-plane sh -c '
  etcdctl --endpoints=https://127.0.0.1:2379 \
   --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
   --key=/etc/kubernetes/pki/etcd/server.key \
   watch /registry/configmaps/default --prefix > /tmp/watch.log 2>&1'

sleep 2
# 터미널 B 역할: 오브젝트 생성 → watch가 즉시 잡습니다
kubectl create configmap probe --from-literal=k=v >/dev/null
sleep 3
docker exec data-control-plane sh -c 'head -6 /tmp/watch.log'
```

예상: PUT 이벤트와 키·값이 즉시 출력. ✅ **watch는 etcd의 1급 기능**(리비전 기반 스트림)이고, K8s의 informer·컨트롤러가 폴링 없이 반응하는 것은 이 위에 서 있습니다(k8s 42의 컨트롤러 원리의 뿌리).

## Step 4. lease — 죽음을 시간으로 감지하는 법

```bash
eval "$ETCDCTL lease grant 10"        # 10초짜리 리스
# 출력의 lease ID를 사용:
LEASE=$(docker exec data-control-plane sh -c '
  etcdctl --endpoints=https://127.0.0.1:2379 \
   --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
   --key=/etc/kubernetes/pki/etcd/server.key lease grant 10' | awk "{print \$2}")

eval "$ETCDCTL put /demo/heartbeat alive --lease=$LEASE"
eval "$ETCDCTL get /demo/heartbeat"     # 존재
echo "12초 대기 (keepalive 없음 = 심장이 멈춤)..."
sleep 12
eval "$ETCDCTL get /demo/heartbeat"     # 사라짐!
```

예상: 12초 후 키가 자동 소멸. ✅ **lease = TTL + keepalive** — K8s의 리더 선출(Lease 오브젝트), 노드 하트비트가 정확히 이 메커니즘입니다. "노드가 죽었다"를 판정하는 것은 사실 "리스가 갱신되지 않았다"입니다.

## Step 5. NATS — 같은 도구, 두 모델

```bash
helm repo add nats https://nats-io.github.io/k8s/helm/charts >/dev/null 2>&1
helm install nats nats/nats -n nats --create-namespace \
  --set config.jetstream.enabled=true >/dev/null
kubectl -n nats rollout status statefulset/nats --timeout=180s

kubectl -n nats run box --image=natsio/nats-box:latest --restart=Never -- sleep 3600
kubectl -n nats wait --for=condition=ready pod/box --timeout=120s
```

### 5-a. 큐 모드 (core NATS) — 소비하면 사라집니다

```bash
kubectl -n nats exec box -- sh -c '
  nats sub -s nats://nats:4222 work --count=1 & sleep 1
  nats pub -s nats://nats:4222 work "job-1"
  sleep 2
  echo "--- 구독자 없이 발행하면? ---"
  nats pub -s nats://nats:4222 work "job-2"
  echo "--- 나중에 구독해도 job-2는 없습니다 (fire-and-forget) ---"
  timeout 3 nats sub -s nats://nats:4222 work --count=1 || echo "수신 없음 ✓"
'
```

예상: job-1은 수신, job-2는 유실 — **구독자가 없으면 메시지는 사라집니다**. 큐/pub-sub의 본질.

### 5-b. 스트림 모드 (JetStream) — 로그에 남습니다

```bash
kubectl -n nats exec box -- sh -c '
  nats -s nats://nats:4222 stream add EVENTS --subjects="events.*" \
    --storage=file --retention=limits --max-msgs=100 --max-bytes=-1 --max-age=1h \
    --discard=old --dupe-window=2m --replicas=1 --no-allow-rollup --no-deny-delete --no-deny-purge >/dev/null 2>&1
  echo "--- 구독자 없이 발행 ---"
  nats -s nats://nats:4222 pub events.a "e1"
  nats -s nats://nats:4222 pub events.a "e2"
  echo "--- 나중에 처음부터 재생 ---"
  nats -s nats://nats:4222 sub events.a --all --count=2 2>/dev/null | head -6
'
```

예상: 나중에 붙은 소비자가 e1·e2를 **처음부터 재생**합니다. ✅ theory §2의 판정 질문("나중에 다시 읽어야 하는가")이 실물로 갈립니다 — 같은 NATS인데 모드가 성격을 바꿉니다.

## Step 6. 산출물 — 오늘 확인한 뿌리와 갈래

```markdown
# etcd에서 확인한 K8s의 뿌리
- /registry/* : 모든 오브젝트가 etcd 키 (상태의 원천)
- watch: 컨트롤러가 폴링하지 않는 이유 (리비전 스트림)
- lease: "노드가 죽었다"의 실체 = 리스 미갱신 (TTL+keepalive)
- 운영 급소: wal fsync 지연 → API 지연 → 컨트롤러 폭주

# NATS에서 확인한 메시징의 갈래
- core(큐): 구독자 없으면 유실 — 가볍고 단순
- JetStream(스트림): 로그에 저장, 나중에 재생 — 저장·운영 비용
- 판정: "이 메시지를 나중에 다시 읽어야 하는가"
```

## 정리

```bash
bash cleanup.sh
```
