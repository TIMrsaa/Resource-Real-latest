# Lab 02 — 묻힌 보석 연쇄 실습

## Step 1. Downward API + projected volume — 자기 인식 Pod

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: self-aware
  labels: { app: self-aware, version: v3 }
spec:
  volumes:
  - name: all-in-one                       # projected: 여러 소스를 한 디렉터리에!
    projected:
      sources:
      - downwardAPI:
          items:
          - { path: labels, fieldRef: { fieldPath: metadata.labels } }
          - { path: cpu_limit, resourceFieldRef: { containerName: app, resource: limits.cpu } }
      - serviceAccountToken:
          path: custom-token
          audience: vault.example.com      # 특정 대상용 토큰! (IRSA의 원리)
          expirationSeconds: 600
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:stable
    command: ["sleep", "3600"]
    resources: { limits: { cpu: 500m, memory: 64Mi } }
    env:
    - { name: MY_POD, valueFrom: { fieldRef: { fieldPath: metadata.name } } }
    - { name: MY_NODE, valueFrom: { fieldRef: { fieldPath: spec.nodeName } } }
    volumeMounts: [{ name: all-in-one, mountPath: /info }]
EOF
kubectl wait --for=condition=Ready pod/self-aware

kubectl exec self-aware -- sh -c 'echo "pod=$MY_POD node=$MY_NODE"; echo; ls /info/; echo; cat /info/labels; echo; cat /info/cpu_limit'
```

예상 출력:
```
pod=self-aware node=ip-192-168-...
labels  cpu_limit  custom-token
app="self-aware"
version="v3"
500m            ← CPU limit를 밀리코어로! (런타임 스레드 수 튜닝의 정석 입력)
```

```bash
# audience 지정 토큰의 내용 확인 (JWT payload 디코딩)
kubectl exec self-aware -- sh -c 'cat /info/custom-token | cut -d. -f2 | base64 -d 2>/dev/null' | python3 -m json.tool 2>/dev/null | grep -E "aud|exp" 
```

예상: `"aud": ["vault.example.com"]` — **수신자를 지정한 단기 토큰.** AWS IRSA가 정확히 이 메커니즘(audience=sts.amazonaws.com)으로 동작합니다 — eks 파트 09의 예고편.

## Step 2. terminationMessagePolicy — describe만으로 사인 확인

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: last-words }
spec:
  restartPolicy: Never
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:stable
    command: ["sh", "-c", "echo 'DB connection failed: timeout to 10.0.5.5:5432'; exit 1"]
    terminationMessagePolicy: FallbackToLogsOnError      # ★ 이 한 줄
EOF
sleep 10
kubectl get pod last-words -o jsonpath='{.status.containerStatuses[0].lastState.terminated.message}'; echo
```

예상 출력:
```
DB connection failed: timeout to 10.0.5.5:5432     ← 로그 마지막 줄이 status에!
```

✅ `kubectl logs --previous`를 칠 필요도 없이 **describe/status에 죽기 직전 로그**가 박힙니다. 모든 운영 컨테이너에 넣어둘 가치가 있는 한 줄.

## Step 3. Topology Aware Routing — AZ 비용 절감 스위치

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: topo
  labels: { app: topo }
spec:
  replicas: 4
  selector:
    matchLabels: { app: topo }
  template:
    metadata:
      labels: { app: topo }
    spec:
      containers:
        - name: agnhost
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          command: ["/agnhost", "netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: topo
spec:
  selector: { app: topo }
  ports:
    - port: 80
      targetPort: 8080
EOF
kubectl annotate svc topo service.kubernetes.io/topology-mode=Auto
sleep 10
kubectl get endpointslices -l kubernetes.io/service-name=topo -o yaml | grep -B2 -A4 "hints"
```

예상 출력 (노드가 멀티 AZ일 때):
```
    hints:
      forZones:
      - name: ap-northeast-2a       ← "이 엔드포인트는 2a 클라이언트에게 우선 배정"
```

✅ EndpointSlice에 **zone 힌트**가 붙고, kube-proxy가 같은 AZ 백엔드를 우선합니다 — AZ 간 전송 비용(GB당 과금!)과 지연을 동시에 줄이는 스위치. 단 백엔드가 AZ별로 충분히 분산돼 있어야 발동합니다(아니면 안전하게 비활성 — hints 없음).

## Step 4. kubectl 보석 5연발

```bash
# ① SSA 소유권 장부 (기본 숨김)
kubectl get deploy topo --show-managed-fields -o jsonpath='{.metadata.managedFields[*].manager}'; echo
# ② SA 단기 토큰 즉석 발급 (CI에서 유용)
kubectl create token default --duration=10m | cut -c1-40; echo "..."
# ③ 조건 충족까지 블로킹 (스크립트의 sleep 루프 대체)
kubectl wait --for=jsonpath='{.status.readyReplicas}'=4 deploy/topo --timeout=60s
# ④ Warning 이벤트만 실시간 관제
timeout 5 kubectl events --watch --types=Warning 2>/dev/null || true
# ⑤ 내 신원 확인
kubectl auth whoami
```

## Step 5. shareProcessNamespace — 사이드카가 앱을 주무르는 법

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: shared-pid }
spec:
  shareProcessNamespace: true              # ★ Pod 내 PID 통합
  containers:
  - name: app
    image: registry.k8s.io/e2e-test-images/agnhost:2.53
    command: ["/agnhost", "netexec", "--http-port=8080"]
  - name: sidecar
    image: public.ecr.aws/docker/library/busybox:stable
    command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/shared-pid
kubectl exec shared-pid -c sidecar -- ps
```

예상: sidecar의 ps에 **app 컨테이너의 프로세스가 보입니다** (PID 분리라는 모듈 03의 기본값을 명시적으로 푼 것). 용도: 사이드카가 앱에 시그널 전송(설정 리로드), 디버깅. ephemeral container의 `--target`과 원리가 같습니다.

## 정리

```bash
bash cleanup.sh
```
