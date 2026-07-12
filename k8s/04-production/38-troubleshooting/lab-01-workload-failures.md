# Lab 01 — 워크로드 장애 5선: 일으키고, 루틴으로 잡기

> 각 시나리오: **일으킵니다 → (멈추고 스스로 진단해봅니다) → 루틴 추적 → 수리 → 교훈**

```bash
kubectl create ns dr-lab    # 실습 격리
```

## 시나리오 1. CrashLoopBackOff

```bash
kubectl run crash -n dr-lab --image=public.ecr.aws/docker/library/busybox:stable \
  -- sh -c 'echo "FATAL: config /etc/app/db.conf not found"; exit 1'
kubectl get pod crash -n dr-lab -w     # Running→Error→CrashLoopBackOff, RESTARTS 증가
```

루틴 추적:
```bash
kubectl describe pod crash -n dr-lab | grep -A4 "Last State"
# → Reason: Error, Exit Code: 1
kubectl logs crash -n dr-lab --previous 2>/dev/null || kubectl logs crash -n dr-lab
# → FATAL: config /etc/app/db.conf not found   ← 유언이 곧 원인
```

✅ **교훈**: exit code 1 + `--previous` 로그 = 앱이 스스로 말한 사인. 재시작 간격이 점점 길어지는 것(BackOff: 10s→20s→40s...→5m cap)도 관찰하세요.

## 시나리오 2. ImagePullBackOff

```bash
kubectl run pull -n dr-lab --image=public.ecr.aws/nginx/nginx:9.99-nonexistent
kubectl get pod pull -n dr-lab    # ErrImagePull → ImagePullBackOff
```

루틴 추적:
```bash
kubectl describe pod pull -n dr-lab | grep -B1 -A2 Failed | head -8
```

예상: `manifest unknown` 또는 `not found` — **사유 문장이 3종을 가릅니다**:
- `manifest unknown / not found` → 태그 오타·없음 (지금 케이스)
- `unauthorized / authentication required` → 프라이빗 레지스트리 권한 (imagePullSecrets/노드 IAM)
- `i/o timeout` → 네트워크 (프록시/방화벽/레지스트리 다운)

수리: `kubectl set image pod/pull pull=public.ecr.aws/nginx/nginx:1.27 -n dr-lab` 대신 Pod 재생성이 깔끔:
```bash
kubectl delete pod pull -n dr-lab
kubectl run pull -n dr-lab --image=public.ecr.aws/nginx/nginx:1.27 && kubectl get pod pull -n dr-lab
```

## 시나리오 3. OOMKilled

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: oom
  namespace: dr-lab
  labels: { run: oom }
spec:
  restartPolicy: Never
  containers:
    - name: oom
      image: polinux/stress
      command: ["stress", "--vm", "1", "--vm-bytes", "250M", "--vm-hang", "1"]
      resources:
        limits: { memory: 100Mi }
EOF
sleep 15; kubectl get pod oom -n dr-lab    # OOMKilled
```

루틴 추적:
```bash
kubectl describe pod oom -n dr-lab | grep -A5 "Last State"
# → Reason: OOMKilled, Exit Code: 137
```

✅ **교훈**: 137 = 128+9(SIGKILL) — 커널이 죽인 것이라 **앱 로그에는 아무 단서가 없습니다**(로그만 보면 미궁). describe의 `OOMKilled`가 유일한 직접 증거. 수리는 limit 상향이 아니라 "왜 250M을 쓰는가"부터(누수 vs 정당한 요구 — 모듈 13의 VPA가 산정 도구).

## 시나리오 4. Pending — 3중 원인 구분

```bash
# 4a. 자원 부족
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: big
  namespace: dr-lab
  labels: { run: big }
spec:
  containers:
    - name: big
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      resources:
        requests: { cpu: "64" }
EOF
kubectl describe pod big -n dr-lab | tail -3
# → 0/N nodes available: N Insufficient cpu.
```

```bash
# 4b. quota 차단 (Pending조차 아닙니다 — Pod가 안 만들어짐!)
kubectl create quota tiny --hard=pods=1 -n dr-lab
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: many
  namespace: dr-lab
  labels: { app: many }
spec:
  replicas: 3
  selector:
    matchLabels: { app: many }
  template:
    metadata:
      labels: { app: many }
    spec:
      containers:
        - name: many
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sleep", "600"]
EOF
kubectl get deploy many -n dr-lab                      # READY 1/3에서 정지
kubectl describe rs -n dr-lab -l app=many | grep -i forbidden | head -1
# → exceeded quota: tiny
```

✅ **교훈**: 같은 "Pod가 모자라다"인데 단서의 위치가 다릅니다 — 자원/taint는 **Pod 이벤트**(스케줄러의 거절), quota는 **ReplicaSet 이벤트**(생성 자체가 거부 — admission, 모듈 21). "Pod가 안 보이면 RS describe"를 기억하세요.

```bash
kubectl delete quota tiny -n dr-lab; kubectl delete deploy many -n dr-lab; kubectl delete pod big -n dr-lab
```

## 시나리오 5. Running인데 503 — readiness의 침묵

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: dr-lab
  labels: { app: web }
spec:
  replicas: 2
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: agnhost
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          command: ["/agnhost", "netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: dr-lab
spec:
  selector: { app: web }
  ports:
    - port: 80
      targetPort: 8080
EOF
# readiness가 "없는 경로"를 보게 — 영원히 NotReady
kubectl patch deploy web -n dr-lab -p '{"spec":{"template":{"spec":{"containers":[{"name":"agnhost","readinessProbe":{"httpGet":{"path":"/nope","port":8080},"periodSeconds":3}}]}}}}'
sleep 20; kubectl get pods -n dr-lab -l app=web    # Running인데 READY 0/1!
```

루틴 추적 (theory §3의 분기점):
```bash
kubectl get endpoints web -n dr-lab     # ENDPOINTS: <none>  ← 범인 확정
kubectl describe pod -n dr-lab -l app=web | grep -A2 Unhealthy | head -4
# → Readiness probe failed: HTTP probe failed with statuscode: 404
```

✅ **교훈**: "Pod는 Running인데 서비스가 안 된다"의 정체 — Running(프로세스 살아있음)과 Ready(트래픽 받을 자격)는 다른 차원입니다(모듈 14). endpoints가 비었다는 한 줄이 진단을 끝냈습니다.

수리:
```bash
kubectl patch deploy web -n dr-lab -p '{"spec":{"template":{"spec":{"containers":[{"name":"agnhost","readinessProbe":{"httpGet":{"path":"/healthz","port":8080}}}]}}}}'
kubectl get endpoints web -n dr-lab    # IP들이 돌아옴
```

## 정리

dr-lab ns는 lab-02에서 계속 씁니다. crash/pull/oom만 정리:
```bash
kubectl delete pod crash pull oom -n dr-lab --ignore-not-found
```
