# Lab 01 — 집행자 활성화, 기본 거부, 선별 허용

## Step 0. VPC CNI의 NetworkPolicy 집행 활성화 (EKS 필수 1회)

```bash
aws eks update-addon --cluster-name k8s-study --region ap-northeast-2 \
  --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy": "true"}'
# 적용 대기 (~2분)
aws eks describe-addon --cluster-name k8s-study --region ap-northeast-2 \
  --addon-name vpc-cni --query 'addon.status'
kubectl get pods -n kube-system -l k8s-app=aws-node \
  -o jsonpath='{.items[0].spec.containers[*].name}'; echo
```

예상 출력:
```
"ACTIVE"
aws-node aws-eks-nodeagent     ← 정책 집행 에이전트가 추가됨
```

> 이 단계를 빼면 **이후 모든 정책이 조용히 무시됩니다** — 직접 확인하고 싶다면 Step 2를 활성화 전에 먼저 해보세요(차단이 안 됩니다).

## Step 1. 실험 무대: shop ns에 3계층 앱

```bash
kubectl create ns shop
for app in frontend api db; do
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $app
  namespace: shop
  labels: { app: $app }
spec:
  containers:
    - name: $app
      image: registry.k8s.io/e2e-test-images/agnhost:2.53
      args: ["netexec", "--http-port=8080"]
EOF
done
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: shop
spec:
  selector: { app: api }
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: shop
spec:
  selector: { app: db }
  ports:
    - port: 80
      targetPort: 8080
EOF
kubectl wait --for=condition=Ready pod --all -n shop

# 현재: 전부 뚫려 있습니다
kubectl exec -n shop frontend -- wget -qO- -T 3 http://api/hostname     # → api
kubectl exec -n shop frontend -- wget -qO- -T 3 http://db/hostname      # → db (frontend가 DB 직접 접근?!)
```

## Step 2. 기본 거부 한 장

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: shop }
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF
sleep 5
kubectl exec -n shop frontend -- wget -qO- -T 3 http://api/hostname
```

예상 출력:
```
wget: download timed out        ← 전부 차단!
```

✅ 빈 podSelector 정책 하나로 ns 전체가 "통제 모드"로 전환됐습니다. 이제 필요한 화살표만 엽니다.

## Step 3. 통신 그래프대로 선별 허용

설계: `frontend → api(8080)`, `api → db(8080)`. frontend→db 직행은 **없음**.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend-to-api, namespace: shop }
spec:
  podSelector: { matchLabels: { app: api } }
  policyTypes: [Ingress]
  ingress:
  - from: [{ podSelector: { matchLabels: { app: frontend } } }]
    ports: [{ protocol: TCP, port: 8080 }]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-api-to-db, namespace: shop }
spec:
  podSelector: { matchLabels: { app: db } }
  policyTypes: [Ingress]
  ingress:
  - from: [{ podSelector: { matchLabels: { app: api } } }]
    ports: [{ protocol: TCP, port: 8080 }]
EOF
sleep 5
```

검증 매트릭스 (예상을 먼저 적고 실행하세요):

```bash
kubectl exec -n shop frontend -- wget -qO- -T 3 http://api/hostname    # ✅ 허용 → api
kubectl exec -n shop api      -- wget -qO- -T 3 http://db/hostname     # ✅ 허용 → db
kubectl exec -n shop frontend -- wget -qO- -T 3 http://db/hostname     # ❌ 차단 → timeout
kubectl exec -n shop db       -- wget -qO- -T 3 http://api/hostname    # ❌ 차단 (db→api 화살표는 안 열었음)
```

✅ **정책 2장이 곧 아키텍처 다이어그램입니다.** frontend가 침해당해도 DB에 직접 손댈 수 없는 구조 — 마이크로 세그멘테이션의 본질.

> 💡 포트 주의: 정책의 port는 **컨테이너 포트(8080)** 기준입니다. Service 포트(80)가 아닙니다 — DNAT 후에 검사되기 때문.

## Step 4. 다른 ns에서의 접근도 차단됐나

```bash
kubectl run outsider --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  sh -c 'wget -qO- -T 3 http://api.shop/hostname || echo BLOCKED'
sleep 8; kubectl logs outsider
```

예상: `BLOCKED` — default ns에서의 접근도 막혔습니다 (모듈 09의 "ns는 안 막아준다" 문제가 드디어 해결).

## 정리

shop ns는 lab-02에서 계속 사용. `kubectl delete pod outsider`만.
