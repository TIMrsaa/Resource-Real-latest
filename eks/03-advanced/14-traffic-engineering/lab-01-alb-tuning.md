# Lab 01 — ALB 경유 측정: 타임아웃의 칼, 알고리즘의 꼬리

13의 도구(vegeta)로 이번엔 **ALB를 통과하는** 경로를 잽니다. 그리고 손잡이 두 개 — idle_timeout과 배분 알고리즘 — 를 돌려 숫자가 변하는 것을 봅니다.

## Step 1. 표적 재구축 — 빠른 타깃 2 + 느린 타깃 1

13의 cleanup으로 지웠으므로 새로 . 이번엔 **일부러 느린 Pod 하나**를 섞습니다(알고리즘 실험의 재료):

```bash
kubectl create ns loadlab
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: podinfo, namespace: loadlab }
spec:
  replicas: 2
  selector: { matchLabels: { app: podinfo, variant: fast } }
  template:
    metadata: { labels: { app: podinfo, variant: fast } }
    spec:
      containers:
      - name: podinfo
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        command: ["./podinfo", "--port=9898", "--level=info"]
        ports: [{ containerPort: 9898 }]
        resources: { requests: { cpu: 200m, memory: 64Mi } }
        readinessProbe: { httpGet: { path: /readyz, port: 9898 } }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: podinfo-slow, namespace: loadlab }
spec:
  replicas: 1
  selector: { matchLabels: { app: podinfo, variant: slow } }
  template:
    metadata: { labels: { app: podinfo, variant: slow } }
    spec:
      containers:
      - name: podinfo
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        command: ["./podinfo", "--port=9898", "--level=info", "--random-delay=true"]   # 0~5초 랜덤 지연
        ports: [{ containerPort: 9898 }]
        resources: { requests: { cpu: 200m, memory: 64Mi } }
        readinessProbe: { httpGet: { path: /readyz, port: 9898 } }
---
apiVersion: v1
kind: Service
metadata: { name: podinfo, namespace: loadlab }
spec:
  selector: { app: podinfo }        # variant 불문 — 세 Pod 모두 타깃
  ports: [{ port: 9898 }]
EOF
kubectl rollout status deploy/podinfo -n loadlab && kubectl rollout status deploy/podinfo-slow -n loadlab
```

## Step 2. ALB 개설 (08의 복습 — 이제 과금 시작)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: podinfo
  namespace: loadlab
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: podinfo, port: { number: 9898 } } }
EOF

# DNS 확보 + 타깃 healthy 대기 (2~3분)
ALB=$(kubectl get ingress podinfo -n loadlab -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
until curl -s -o /dev/null -w "%{http_code}" http://$ALB/healthz | grep -q 200; do sleep 10; done
echo "ALB ready: $ALB"
```

## Step 3. 손잡이 ① — idle_timeout이 긴 요청을 자르는 순간

```bash
# 정상: 3초 걸리는 요청 (기본 idle 60s 안)
curl -s -o /dev/null -w "code=%{http_code} time=%{time_total}s\n" http://$ALB/delay/3

# idle_timeout을 5초로 조이면?
kubectl annotate ingress podinfo -n loadlab --overwrite \
  "alb.ingress.kubernetes.io/load-balancer-attributes=idle_timeout.timeout_seconds=5"
sleep 60    # 컨트롤러 reconcile 대기
curl -s -o /dev/null -w "code=%{http_code} time=%{time_total}s\n" http://$ALB/delay/8
```

예상: `code=504 time=~5s` — 앱은 8초 뒤 멀쩡히 답하려 했지만, **ALB가 5초에 전화를 끊고 유저에게 504를 답했습니다.** theory §2의 그 칼. 원복:

```bash
kubectl annotate ingress podinfo -n loadlab --overwrite \
  "alb.ingress.kubernetes.io/load-balancer-attributes=idle_timeout.timeout_seconds=60"
```

✅ "긴 요청이 있는 서비스의 idle_timeout은 **최장 요청 시간보다 길게**" — 그리고 keep-alive 부등식(앱 > ALB)은 반대 방향의 사고(502)를 막는다는 것까지 묶어서 기억.

## Step 4. 손잡이 ② — RR vs LOR: 느린 타깃 하나가 만드는 꼬리

지금 타깃 3개 중 1개가 랜덤 0~5초 지연입니다. 기본(round_robin)으로 측정:

```bash
kubectl run vegeta --rm -i --restart=Never -n loadlab \
  --image=peterevans/vegeta:latest --requests=cpu=500m -- sh -c \
  "echo 'GET http://$ALB/' | vegeta attack -rate=60 -duration=60s | vegeta report"
```

기록: p50 / p95 / p99. 예상 — 요청의 약 1/3이 느린 타깃에 배정되므로 **p95~p99가 초 단위**.

이제 LOR로 전환하고 같은 측정:

```bash
kubectl annotate ingress podinfo -n loadlab --overwrite \
  "alb.ingress.kubernetes.io/target-group-attributes=load_balancing.algorithm.type=least_outstanding_requests"
sleep 60
kubectl run vegeta --rm -i --restart=Never -n loadlab \
  --image=peterevans/vegeta:latest --requests=cpu=500m -- sh -c \
  "echo 'GET http://$ALB/' | vegeta attack -rate=60 -duration=60s | vegeta report"
```

```markdown
| 알고리즘 | p50 | p95 | p99 | 해석 |
|----------|-----|-----|-----|------|
| round_robin | ~ms | 초 단위 | 초 단위 | 느린 타깃도 1/3 몫을 받습니다 |
| least_outstanding | ~ms | ↓↓ | ↓↓ | 느린 타깃은 outstanding이 쌓여 배정에서 밀립니다 |
```

✅ **같은 Pod, 같은 부하, 배분만 바꿨는데 꼬리가 잘렸습니다.** 원리는 Little's Law(13): 느린 타깃일수록 in-flight가 쌓이고, LOR은 그걸 신호로 읽습니다. GC 멈춤·식은 캐시·시끄러운 이웃 — 현실의 "느린 타깃 하나"는 늘 있으므로, 지연 민감 서비스의 기본값으로 LOR을 검토할 가치가 있습니다 (단, slow_start와 택일 — theory §4).

## Step 5. 잔재 정리 (lab-02가 이어받습니다)

느린 타깃은 실험 종료 — 변수 통제:

```bash
kubectl scale deploy/podinfo-slow -n loadlab --replicas=0
```

Ingress/ALB는 lab-02에서 계속 씁니다. **여기서 세션을 끊는다면 반드시 cleanup.sh** — ALB는 시간당 과금입니다.
