# Lab 01 — istiod와 트래픽 관리: CRD가 Envoy 설정이 되는 것을 봅니다

23에서 배운 config_dump를 이제 메시에서 씁니다 — VirtualService를 만들고 그것이 사이드카의 route가 되는 것을 확인합니다.

전제: kind, kubectl, istioctl(`brew install istioctl` 또는 릴리스). 메모리 8GB+.

## Step 1. 클러스터와 Istio

```bash
kind create cluster --name istio -q
istioctl install --set profile=demo -y
kubectl -n istio-system get pods
```

✅ `istiod`(컨트롤플레인)와 게이트웨이들. istiod가 theory §1의 세 역할을 합니다.

## Step 2. 사이드카 주입 — 투명한 가로채기

```bash
kubectl create ns demo
kubectl label ns demo istio-injection=enabled     # ★ 이 라벨이 주입을 켭니다

kubectl -n demo apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: reviews-v1, labels: { app: reviews, version: v1 } }
spec:
  replicas: 1
  selector: { matchLabels: { app: reviews, version: v1 } }
  template:
    metadata: { labels: { app: reviews, version: v1 } }
    spec: { containers: [{ name: c, image: hashicorp/http-echo, args: ["-text=reviews-v1","-listen=:9080"] }] }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: reviews-v2, labels: { app: reviews, version: v2 } }
spec:
  replicas: 1
  selector: { matchLabels: { app: reviews, version: v2 } }
  template:
    metadata: { labels: { app: reviews, version: v2 } }
    spec: { containers: [{ name: c, image: hashicorp/http-echo, args: ["-text=reviews-v2","-listen=:9080"] }] }
---
apiVersion: v1
kind: Service
metadata: { name: reviews }
spec: { selector: { app: reviews }, ports: [{ port: 9080 }] }
EOF
kubectl -n demo rollout status deploy/reviews-v1 --timeout=120s
kubectl -n demo rollout status deploy/reviews-v2 --timeout=120s

echo "=== Pod에 컨테이너가 몇 개? ==="
kubectl -n demo get pod -l app=reviews -o jsonpath='{.items[0].spec.containers[*].name}'; echo
```

예상: `c istio-proxy` — **앱 컨테이너 옆에 Envoy가 자동 주입**됐습니다(theory §1). 앱은 이것을 모릅니다.

## Step 3. 클라이언트 + 기본 라우팅

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: demo
  labels: { run: client }
spec:
  containers:
    - name: client
      image: curlimages/curl
      command: ["sleep", "3600"]
EOF
kubectl -n demo wait --for=condition=ready pod/client --timeout=120s

echo "=== 정책 없음: v1/v2 무작위 분산 ==="
for i in $(seq 1 10); do kubectl -n demo exec client -- curl -s reviews:9080; echo; done | sort | uniq -c
```

## Step 4. VirtualService — 90/10 카나리

```bash
kubectl -n demo apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: { name: reviews }
spec:
  host: reviews
  subsets:
    - { name: v1, labels: { version: v1 } }
    - { name: v2, labels: { version: v2 } }
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: { name: reviews }
spec:
  hosts: [reviews]
  http:
    - route:
        - { destination: { host: reviews, subset: v1 }, weight: 90 }
        - { destination: { host: reviews, subset: v2 }, weight: 10 }
EOF
sleep 8

echo "=== 90/10 분할 확인 ==="
for i in $(seq 1 30); do kubectl -n demo exec client -- curl -s reviews:9080; echo; done | sort | uniq -c
```

예상: v1 ~27, v2 ~3. ✅ 카나리(17의 Progressive Delivery가 이 위에 지어집니다).

## Step 5. ★ CRD가 Envoy 설정이 되었는가 — config_dump

```bash
echo "=== istioctl로 사이드카의 실제 route 설정 보기 ==="
istioctl proxy-config route deploy/reviews-v1 -n demo 2>/dev/null | grep -A1 reviews | head -6 || \
  istioctl proxy-config route $(kubectl -n demo get pod -l app=client -o name | head -1 | cut -d/ -f2) -n demo 2>/dev/null | head -10

echo ""
echo "=== client 사이드카가 본 reviews 라우트 (가중치!) ==="
CLIENT=$(kubectl -n demo get pod -l run=client -o name | head -1 | cut -d/ -f2)
istioctl proxy-config route $CLIENT -n demo --name 9080 -o json 2>/dev/null | \
  python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    for rc in d:
        for vh in rc.get('virtualHosts',[]):
            if 'reviews' in vh.get('name',''):
                for r in vh.get('routes',[]):
                    wc = r.get('route',{}).get('weightedClusters',{})
                    for c in wc.get('clusters',[]):
                        print(f\"  {c['name']}: weight {c.get('weight')}\")
except: print('  (istioctl proxy-config route 출력을 직접 확인하세요)')
" 2>/dev/null || echo "  istioctl proxy-config route $CLIENT -n demo 로 직접 확인"
```

✅ **VirtualService의 90/10이 사이드카 Envoy의 weighted cluster로 번역됐습니다**(theory §2). 23에서 배운 config_dump가 메시 디버깅의 핵심인 이유 — CRD(의도)와 실제 Envoy 설정(실체)을 대조하는 것.

## Step 6. cluster 설정 — DestinationRule의 번역

```bash
echo "=== client 사이드카의 cluster (서브셋) ==="
istioctl proxy-config cluster $CLIENT -n demo 2>/dev/null | grep reviews | head -4

echo ""
echo "=== endpoint (실제 Pod IP) ==="
istioctl proxy-config endpoint $CLIENT -n demo 2>/dev/null | grep 9080 | head -4
```

✅ 23의 4계층(listener/route/cluster/endpoint)이 메시에서 그대로 — `istioctl proxy-config {route,cluster,endpoint,listener}`가 각 계층을 보여줍니다.

## Step 7. 고급 트래픽 — 헤더 기반·미러링

```bash
kubectl -n demo apply -f - <<'EOF'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: { name: reviews }
spec:
  hosts: [reviews]
  http:
    - match: [{ headers: { x-user: { exact: tester } } }]   # 특정 헤더는 v2로
      route: [{ destination: { host: reviews, subset: v2 } }]
    - route: [{ destination: { host: reviews, subset: v1 } }]  # 나머지는 v1
      mirror: { host: reviews, subset: v2 }                    # ★ v2로 미러링(응답 무시)
      mirrorPercentage: { value: 100 }
EOF
sleep 8

echo "=== 일반 요청 (v1) ==="
kubectl -n demo exec client -- curl -s reviews:9080; echo
echo "=== x-user: tester 헤더 (v2) ==="
kubectl -n demo exec client -- curl -s -H "x-user: tester" reviews:9080; echo
echo "→ 미러링: v1 응답을 받으면서 v2에도 복사 전송(shadow traffic) — 신버전 부하 테스트"
```

✅ 헤더 기반 라우팅과 미러링 — eks 20에서 사용자로 만진 기능들이 전부 Envoy route 설정으로 환원됩니다.

## Step 8. 산출물

```markdown
# Istio 트래픽 관리 카드
- istio-injection=enabled → 사이드카 자동 주입 (앱 무수정)
- VirtualService → Envoy route (가중치·헤더·미러)
- DestinationRule → Envoy cluster (서브셋·LB·아웃라이어)
- 디버깅: istioctl proxy-config {route,cluster,endpoint,listener} <pod>
  = 23의 config_dump 요약 — CRD(의도) vs Envoy(실체) 대조
- 카나리는 Argo Rollouts(17)가 이 CRD들을 조작해 자동화
```

## 정리

lab-02에서 보안과 ambient를 다룹니다. 유지.
