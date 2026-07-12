# Lab 01 — Probe 3종의 동작과 오동작

> agnhost 이미지의 `/healthz`(항상 200)와 제어 가능한 엔드포인트를 활용합니다.

## Step 1. readiness 실패 = 트래픽 차단 (재시작 아님!)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: probe-demo }
spec:
  replicas: 2
  selector: { matchLabels: { app: probe-demo } }
  template:
    metadata: { labels: { app: probe-demo } }
    spec:
      containers:
      - name: app
        image: registry.k8s.io/e2e-test-images/agnhost:2.53
        args: ["netexec", "--http-port=8080"]
        ports: [{ containerPort: 8080 }]
        readinessProbe:
          httpGet: { path: /healthz, port: 8080 }
          periodSeconds: 2
          failureThreshold: 2
---
apiVersion: v1
kind: Service
metadata: { name: probe-demo }
spec:
  selector: { app: probe-demo }
  ports: [{ port: 80, targetPort: 8080 }]
EOF
kubectl wait --for=condition=Available deploy/probe-demo
kubectl get endpointslices -l kubernetes.io/service-name=probe-demo
```

예상: ENDPOINTS에 Pod IP 2개.

```bash
# Pod 하나를 일부러 "준비 안 됨"으로: agnhost는 /healthz를 N초간 500으로 만드는 기능이 있습니다
POD=$(kubectl get pod -l app=probe-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- wget -qO- "http://localhost:8080/makeUnhealthy?duration=30s" 2>/dev/null \
  || kubectl exec $POD -- sh -c 'wget -qO- "http://localhost:8080/exit?code=0&timeout=0" >/dev/null 2>&1 || true'
# (agnhost 버전에 따라 경로가 다르면 단순 대체: readiness 경로를 잘못된 것으로 patch)
kubectl patch deploy probe-demo --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/nope"}]'
sleep 15; kubectl get pods -l app=probe-demo
```

예상 출력:
```
probe-demo-...   0/1   Running   0     ← READY 0/1, RESTARTS는 0!
```

```bash
kubectl get endpointslices -l kubernetes.io/service-name=probe-demo
```

✅ **READY 0/1 + RESTARTS 0 + 명단 제외** — readiness의 3대 특징을 한 번에 확인. 복구:

```bash
kubectl patch deploy probe-demo --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/healthz"}]'
kubectl rollout status deploy/probe-demo
```

## Step 2. liveness 실패 = 재시작

```bash
kubectl patch deploy probe-demo --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/livenessProbe","value":{"httpGet":{"path":"/nope","port":8080},"periodSeconds":3,"failureThreshold":2}}]'
kubectl rollout status deploy/probe-demo --timeout=30s; kubectl get pods -l app=probe-demo -w
```

예상 출력 (시간 흐름):
```
probe-demo-...   1/1   Running   1 (10s ago)     ← RESTARTS 증가 시작
probe-demo-...   1/1   Running   2 (8s ago)
probe-demo-...   0/1   CrashLoopBackOff   3      ← 반복 재시작 → 백오프
```

(Ctrl+C로 관찰 종료)

```bash
kubectl describe pod -l app=probe-demo | grep -m2 -E "Killing|Unhealthy"
# → Liveness probe failed... / Container app failed liveness probe, will be restarted
```

✅ readiness(차단)와 liveness(처형)의 차이를 RESTARTS 숫자로 체감. **잘못된 liveness 하나가 멀쩡한 앱을 CrashLoop으로 만듭니다** — "재시작 폭풍"의 축소판입니다. 복구:

```bash
kubectl patch deploy probe-demo --type=json -p='[{"op":"remove","path":"/spec/template/spec/containers/0/livenessProbe"}]'
```

## Step 3. startup probe — 느린 기동 시뮬레이션

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: slow-boot }
spec:
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:stable
    # 40초 걸려 "기동"한 후 파일 생성 → 그때부터 건강
    command: ["sh", "-c", "sleep 40 && touch /tmp/ready && sleep 3600"]
    startupProbe:
      exec: { command: [cat, /tmp/ready] }
      periodSeconds: 5
      failureThreshold: 12          # 최대 60초 유예
    livenessProbe:
      exec: { command: [cat, /tmp/ready] }
      periodSeconds: 5
      failureThreshold: 1           # 매우 엄격 — 그러나 startup이 막아줌
EOF
kubectl get pod slow-boot -w
```

예상: 40여 초간 `Running`(READY 0/1)을 유지하다 **재시작 없이** 1/1 — startup이 liveness를 보류시킨 덕분. startup probe를 지우고 다시 만들면 40초를 못 버티고 RESTARTS가 올라가는 것도 확인해보세요.

## 정리

```bash
kubectl delete pod slow-boot --ignore-not-found
# probe-demo는 lab-02에서 계속 사용
```
