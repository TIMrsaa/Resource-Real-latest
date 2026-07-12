# Lab 01 — 빌딩블록 체험: 사이드카, state, pub/sub

앱이 localhost의 Dapr에 표준 API로 말하고, Dapr가 백엔드를 처리하는 것을 직접 봅니다.

전제: kind, kubectl, helm.

## Step 1. 클러스터와 Dapr

```bash
kind create cluster --name dapr -q

helm repo add dapr https://dapr.github.io/helm-charts >/dev/null 2>&1
helm install dapr dapr/dapr -n dapr-system --create-namespace --wait >/dev/null
kubectl -n dapr-system get pods
echo ""
echo "=== 컨트롤 플레인 (theory §1) ==="
cat <<'EOF'
  dapr-operator          Component/Configuration CRD 관리
  dapr-sidecar-injector  Pod에 daprd 주입
  dapr-placement         actor 배치
  dapr-sentry            mTLS 인증서
EOF
```

## Step 2. 백엔드(Redis) + State 컴포넌트

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1
helm install redis bitnami/redis -n default \
  --set auth.enabled=false --set architecture=standalone >/dev/null
kubectl rollout status statefulset/redis-master --timeout=180s

# State store 컴포넌트 (Redis 뒤에)
kubectl apply -f - <<'EOF'
apiVersion: dapr.io/v1alpha1
kind: Component
metadata: { name: statestore }
spec:
  type: state.redis          # ★ 백엔드를 여기서 지정
  version: v1
  metadata:
    - { name: redisHost, value: "redis-master:6379" }
    - { name: redisPassword, value: "" }
---
apiVersion: dapr.io/v1alpha1
kind: Component
metadata: { name: pubsub }
spec:
  type: pubsub.redis         # pub/sub도 Redis 뒤에
  version: v1
  metadata:
    - { name: redisHost, value: "redis-master:6379" }
    - { name: redisPassword, value: "" }
EOF
```

## Step 3. Dapr 사이드카가 주입된 앱

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: app }
spec:
  replicas: 1
  selector: { matchLabels: { app: app } }
  template:
    metadata:
      labels: { app: app }
      annotations:
        dapr.io/enabled: "true"        # ★ 사이드카 주입
        dapr.io/app-id: "myapp"
        dapr.io/app-port: "8080"
    spec:
      containers:
        - name: app
          image: curlimages/curl
          command: ["sleep","3600"]
          ports: [{ containerPort: 8080 }]
EOF
kubectl rollout status deploy/app --timeout=120s

echo "=== Pod의 컨테이너 (daprd 사이드카) ==="
kubectl get pod -l app=app -o jsonpath='{.items[0].spec.containers[*].name}'; echo
```

예상: `app daprd` — Dapr 사이드카가 주입됐습니다(theory §1).

## Step 4. State — localhost API로 상태 저장

```bash
POD=$(kubectl get pod -l app=app -o name | head -1)

echo "=== 상태 저장 (앱은 Redis를 모릅니다, Dapr에 말할 뿐) ==="
kubectl exec $POD -c app -- curl -s -X POST http://localhost:3500/v1.0/state/statestore \
  -H "Content-Type: application/json" \
  -d '[{"key":"order-1","value":{"item":"book","qty":3}}]'
echo "저장 완료"

echo ""
echo "=== 상태 조회 ==="
kubectl exec $POD -c app -- curl -s http://localhost:3500/v1.0/state/statestore/order-1
echo ""

echo ""
echo "=== Redis에 실제로 저장됐는지 확인 (Dapr가 백엔드 처리) ==="
kubectl exec statefulset/redis-master -- redis-cli KEYS "*order*" 2>/dev/null | head -3
```

예상: 저장·조회 성공, Redis에 `myapp||order-1` 키 존재. ✅ **앱은 `localhost:3500`의 표준 API만 호출**했고, Dapr가 Redis를 처리했습니다(theory §2). 앱 코드에 Redis 클라이언트가 없습니다.

## Step 5. Pub/sub — 발행과 구독

```bash
# 구독 앱 (Dapr가 메시지를 앱으로 전달)
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: subscriber }
spec:
  replicas: 1
  selector: { matchLabels: { app: subscriber } }
  template:
    metadata:
      labels: { app: subscriber }
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "subscriber"
        dapr.io/app-port: "8080"
    spec:
      containers:
        - name: app
          image: hashicorp/http-echo
          args: ["-text=received", "-listen=:8080"]
          ports: [{ containerPort: 8080 }]
EOF
kubectl rollout status deploy/subscriber --timeout=120s

echo "=== 메시지 발행 (앱은 Kafka/Redis를 모릅니다) ==="
kubectl exec $POD -c app -- curl -s -X POST \
  http://localhost:3500/v1.0/publish/pubsub/orders \
  -H "Content-Type: application/json" \
  -d '{"orderId":"123","item":"book"}'
echo "발행 완료"

echo ""
echo "=== Redis pub/sub 확인 ==="
kubectl exec statefulset/redis-master -- redis-cli XLEN "orders" 2>/dev/null || \
  echo "(pub/sub 메시지가 Redis stream에)"
```

✅ **발행도 표준 API** — 앱은 브로커가 Redis인지 Kafka인지 모릅니다(theory §2, 09의 pub/sub이 Dapr 뒤로).

## Step 6. 시크릿 빌딩블록 (22와 연결)

```bash
kubectl create secret generic app-secret --from-literal=api-key=super-secret >/dev/null

kubectl apply -f - <<'EOF'
apiVersion: dapr.io/v1alpha1
kind: Component
metadata: { name: k8s-secrets }
spec:
  type: secretstores.kubernetes
  version: v1
EOF
sleep 5

echo "=== 시크릿 읽기 (표준 API — 백엔드는 K8s Secret) ==="
kubectl exec $POD -c app -- curl -s \
  http://localhost:3500/v1.0/secrets/k8s-secrets/app-secret 2>/dev/null || \
  echo "(RBAC 설정에 따라 — 개념: secretstores.kubernetes를 vault로 바꾸면 Vault에서)"
echo ""
echo "→ 22의 시크릿을 표준 API로. 백엔드(K8s/Vault/AWS SM)를 컴포넌트로 교체"
```

## Step 7. 산출물

```markdown
# Dapr 빌딩블록 카드
- 사이드카(daprd) 주입: annotation (dapr.io/enabled)
- 앱 → localhost:3500 표준 API → daprd가 백엔드 처리
- State: PUT /v1.0/state/<store> (Redis·DynamoDB... 뒤에)
- Pub/sub: POST /v1.0/publish/<broker>/<topic> (Kafka·NATS... 뒤에 — 09)
- Secrets: GET /v1.0/secrets/<store>/<key> (K8s·Vault... 뒤에 — 22)
- 앱은 백엔드를 모릅니다 (언어 무관, HTTP만)
```

## 정리

lab-02에서 백엔드 교체(이식성)와 메시와의 차이를 다룹니다. 유지.
