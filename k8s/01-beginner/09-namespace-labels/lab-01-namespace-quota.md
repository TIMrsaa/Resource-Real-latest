# Lab 01 — Namespace 격리의 실제 범위 + Quota

## Step 1. ns 생성과 이름 충돌 해결 확인

```bash
kubectl create namespace dev
kubectl create namespace staging

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: dev
  labels: { app: web }
spec:
  replicas: 1
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: nginx
          image: public.ecr.aws/nginx/nginx:1.27
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: staging               # 같은 이름 — 다른 namespace라 공존 가능
  labels: { app: web }
spec:
  replicas: 1
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: nginx
          image: public.ecr.aws/nginx/nginx:1.27
EOF
kubectl get deploy -A | grep web
```

예상 출력:
```
dev       web   1/1   ...
staging   web   1/1   ...      ← 같은 이름이 공존
```

## Step 2. 네트워크는 격리되지 않습니다 (중요 실험)

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: staging
spec:
  selector: { app: web }
  ports:
    - port: 80
EOF
# dev의 Pod에서 staging의 Service 호출
kubectl run -n dev tester --rm -it --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  wget -qO- -T 5 http://web.staging.svc.cluster.local | head -4
```

예상 출력:
```
<!DOCTYPE html>
<title>Welcome to nginx!</title> ...      ← 그냥 됩니다!
```

✅ **이 모듈의 핵심 한 방**: ns는 벽이 아닙니다. `<svc>.<ns>.svc.cluster.local` 이면 어디서든 접속. 격리하려면 NetworkPolicy(모듈 15).

## Step 3. ResourceQuota — 총량 한도

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata: { name: dev-quota, namespace: dev }
spec:
  hard:
    pods: "3"
    requests.cpu: "500m"
    services.loadbalancers: "0"
EOF
kubectl describe quota dev-quota -n dev
```

```bash
# 한도 시험 ① Pod 수: replicas 5로 올려보기
kubectl scale deployment web -n dev --replicas=5
sleep 5; kubectl get deploy,rs -n dev
```

예상 출력:
```
deploy/web   ?/5   ...    ← 5가 못 됨
rs/web-...   5 desired, 2~3 current
```

```bash
kubectl describe rs -n dev | grep -A 2 "FailedCreate" | head -5
```

예상:
```
Error creating: pods "web-..." is forbidden: exceeded quota: dev-quota,
requested: pods=1, used: pods=3, limited: pods=3
```

✅ 거부의 주체는 **admission**(모듈 02의 API 파이프라인) — 저장 전에 막습니다. RS는 포기하지 않고 재시도를 계속합니다(조정 루프!) — 쿼터를 늘리면 자동으로 채워집니다.

```bash
# 한도 시험 ② LB 금지 (비용 가드레일로 유용)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web-lb
  namespace: dev
spec:
  type: LoadBalancer               # ← quota가 거부해야 정상
  selector: { app: web }
  ports:
    - port: 80
EOF
```

예상: `forbidden: exceeded quota ... services.loadbalancers=0` — **학습용 ns에 LB 금지 걸기, 강력 추천.**

## Step 4. LimitRange — 기본값 주입

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata: { name: defaults, namespace: dev }
spec:
  limits:
  - type: Container
    defaultRequest: { cpu: 50m, memory: 64Mi }
    default: { memory: 128Mi }
EOF

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: plain
  namespace: dev
  labels: { run: plain }
spec:
  containers:
    - name: plain
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
EOF
kubectl get pod plain -n dev -o jsonpath='{.spec.containers[0].resources}' | python -m json.tool 2>/dev/null \
  || kubectl get pod plain -n dev -o jsonpath='{.spec.containers[0].resources}'
```

예상 출력:
```json
{"limits":{"memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}
```

✅ 아무것도 안 적은 Pod에 기본값이 **자동 주입**됐습니다 (mutating admission의 실례).

## Step 5. ns 기본값 설정 (편의)

```bash
kubectl config set-context --current --namespace=dev
kubectl get pods            # -n dev 없이 dev가 보임
kubectl config set-context --current --namespace=default   # 원복
```

## 정리

```bash
kubectl scale deployment web -n dev --replicas=1
# ns는 lab-02에서 계속 사용
```
