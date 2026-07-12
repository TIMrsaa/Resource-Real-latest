# Lab 01 — 설치, 주입, 그리고 STRICT의 문턱

Istio를 최소로 깔고 — sidecar가 **끼어드는** 순간과, mTLS가 STRICT로 조여질 때 **메시 밖 평문이 거부되는** 순간을 실측합니다.

## Step 1. istioctl과 최소 설치

```bash
# istioctl 설치 (https://istio.io/latest/docs/setup/getting-started/)
curl -L https://istio.io/downloadIstio | sh -
cd istio-* && export PATH=$PWD/bin:$PATH

istioctl install --set profile=minimal -y      # istiod만 — 게이트웨이 없이
kubectl get pods -n istio-system               # istiod 1개
```

## Step 2. 주입 전/후 — 웹훅이 끼워 넣는 것

```bash
kubectl create ns meshlab

# 주입 라벨 "없이" 먼저
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: meshlab
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
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
EOF
kubectl get pods -n meshlab    # READY 1/1 — 컨테이너 하나

# ns에 주입 라벨 → "새로 생성되는" Pod부터 적용 (webhook은 생성 시점에만 — k8s 23)
kubectl label ns meshlab istio-injection=enabled
kubectl rollout restart deploy/web -n meshlab
kubectl rollout status deploy/web -n meshlab
kubectl get pods -n meshlab    # READY 2/2 ← Envoy가 옆자리에!
kubectl get pod -n meshlab -l app=web -o jsonpath='{.items[0].spec.containers[*].name}'; echo
```

예상: `podinfo istio-proxy` — mutating webhook이 Pod 생성 요청을 **가로채 컨테이너를 추가**했습니다. 23에서 배운 그 메커니즘의 최대 규모 사용처.

## Step 3. 통신은 그대로 — 단, 이제 비서를 거칩니다

```bash
# 클라이언트도 메시 안에 하나
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client
  namespace: meshlab
  labels: { app: client }
spec:
  replicas: 1
  selector:
    matchLabels: { app: client }
  template:
    metadata:
      labels: { app: client }
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: meshlab
spec:
  selector: { app: web }
  ports:
    - port: 9898
EOF
kubectl rollout status deploy/client -n meshlab

kubectl exec -n meshlab deploy/client -c podinfo -- curl -s http://web:9898/ | head -3
```

정상 응답 — 앱은 아무것도 모르지만, 이 호출은 이미 client의 Envoy → web의 Envoy를 거쳤고 **자동으로 mTLS**였습니다(기본 PERMISSIVE에서 메시 내부끼리는 mTLS 선호). 증명:

```bash
istioctl proxy-config secret deploy/web -n meshlab | head -5   # SA 기반 인증서 (자동 발급)
```

`spiffe://cluster.local/ns/meshlab/sa/default` — 신원이 IP가 아니라 **ServiceAccount**입니다(theory §3).

## Step 4. 침입자 실험 — PERMISSIVE의 관용

메시 **밖**(sidecar 없는) Pod에서 접근하면?

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: outsider              # default ns — 사이드카 주입 없음
  labels: { run: outsider }
spec:
  containers:
    - name: outsider
      image: ghcr.io/stefanprodan/podinfo:6.7.1
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/outsider --timeout=60s
kubectl exec outsider -- curl -s -m3 -o /dev/null -w "%{http_code}\n" http://web.meshlab:9898/
```

예상: `200` — PERMISSIVE는 평문도 받습니다. 이행기의 관용이자, 보안 관점에선 **아직 잠기지 않은 문**.

## Step 5. STRICT — 문을 잠급니다

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: { name: default, namespace: meshlab }
spec:
  mtls: { mode: STRICT }
EOF
sleep 5

# 메시 안: 여전히 정상
kubectl exec -n meshlab deploy/client -c podinfo -- curl -s -m3 -o /dev/null -w "in-mesh: %{http_code}\n" http://web:9898/
# 메시 밖: 이제 거부
kubectl exec outsider -- curl -s -m3 -o /dev/null -w "outsider: %{http_code}\n" http://web.meshlab:9898/ || echo "outsider: BLOCKED"
```

예상:

```
in-mesh: 200
outsider: BLOCKED (connection reset)
```

✅ **신원 없는 평문은 TCP 수준에서 리셋**됩니다 — 애플리케이션 인증 코드 0줄로 "메시 멤버만 대화 가능"이 강제됐습니다. NetworkPolicy(15)가 "어느 주소가"를 묻는다면, 이것은 "누구인지 증명했는가"를 묻습니다 — 겹층 방어의 두 번째 층.

## Step 6. 도입 절차 기록 (산출물)

```markdown
# mTLS 도입 runbook
1. istiod 설치 → 대상 ns 라벨 → 롤링 재시작 (2/2 확인)
2. PERMISSIVE 상태에서 전 서비스 정상 확인 + Kiali/메트릭으로 mTLS 비율 관찰
3. ns 단위 STRICT (전역은 마지막) — 메시 밖 정당한 호출자(cron, 레거시)를 먼저 색출!
4. 검증: in-mesh 200 / outsider RESET (이 랩의 그 두 줄)
5. 예외는 PeerAuthentication의 portLevelMtls로 좁게 — "전역 PERMISSIVE 방치" 금지
```

## 정리

meshlab·outsider는 lab-02에서 계속 씁니다.
