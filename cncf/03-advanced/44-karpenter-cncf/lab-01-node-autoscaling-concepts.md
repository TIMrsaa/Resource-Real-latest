# Lab 01 — 노드 오토스케일링의 원리: Pending Pod와 스케줄링

> 실제 노드 프로비저닝은 클라우드가 필요하므로, 이 랩은 kind에서 **Karpenter가 반응하는 신호(Pending Pod)** 와 **08 스케줄링 제약**을 직접 만들어, 노드 오토스케일러가 무엇을 보고 어떻게 결정하는지 원리를 익힙니다.

## 0. 준비

```bash
kind create cluster --name karpenter
# kind는 노드가 고정이라 실제 스케일은 안 되지만, 스케줄링·Pending 원리는 관찰 가능
kubectl get nodes
# karpenter-control-plane   Ready
```

## 1. Pending Pod 만들기 — 노드 오토스케일러가 반응하는 신호

```bash
# 노드 용량을 초과하는 리소스를 요청 → Pod가 Pending
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hungry
spec:
  replicas: 5
  selector: { matchLabels: { app: hungry } }
  template:
    metadata: { labels: { app: hungry } }
    spec:
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.9
          resources:
            requests:
              cpu: "2"          # 각 Pod가 2 CPU 요구 (08의 requests)
              memory: "2Gi"
EOF

# 노드 용량을 넘는 Pod들이 Pending
kubectl get pod -l app=hungry
# NAME          READY   STATUS    ...
# hungry-xxx    0/1     Running   ← 노드에 맞는 만큼만
# hungry-yyy    0/1     Pending   ← 용량 부족! (이게 Karpenter의 신호)

kubectl get pod -l app=hungry -o wide | grep Pending
kubectl describe pod -l app=hungry | grep -A3 Events
# Warning  FailedScheduling  Insufficient cpu
# → "노드에 CPU가 부족" = Karpenter가 있었다면 노드를 프로비저닝할 신호
```

**핵심** — `Pending` + `Insufficient cpu`가 노드 오토스케일러의 트리거입니다. 실제 Karpenter라면 이 시점에 "이 5개 Pod(각 2CPU/2Gi)를 놓으려면 어떤 노드가 필요한가"를 계산해 노드를 만듭니다.

## 2. Karpenter의 계산을 손으로 — 빈패킹

```
Pending Pod 요구: 각 2 CPU / 2Gi, 5개 → 총 10 CPU / 10Gi 필요

Karpenter의 선택지 (예시, 실제 클라우드라면):
  옵션 A: 4vCPU/16Gi 노드 3개 = 12 CPU (2 낭비) 
  옵션 B: 8vCPU/32Gi 노드 2개 = 16 CPU (6 낭비, 하지만 관리 단순)
  옵션 C: 16vCPU/64Gi 노드 1개 = 여유 (스팟이면 저렴)
  → 가격·빈패킹·중단 위험을 종합해 최적 선택

Cluster Autoscaler라면:
  노드그룹이 4vCPU 고정 → 3개 추가 (선택지 없음)
  → Karpenter는 타입까지 고르니 더 최적
```

이 계산이 Karpenter가 08의 스케줄링을 "역방향"으로 푸는 것입니다 — Pod 제약에서 노드를 도출.

## 3. 스케줄 제약이 노드 선택을 좌우 (08)

```bash
# nodeSelector·taint 같은 제약이 있으면 노드도 그에 맞춰야
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: arm-workload
spec:
  nodeSelector:
    kubernetes.io/arch: arm64      # ARM 노드를 요구
  containers:
    - name: app
      image: registry.k8s.io/pause:3.9
      resources: { requests: { cpu: "1" } }
EOF

kubectl describe pod arm-workload | grep -A3 Events
# (kind 노드가 arm64가 아니면) Pending — node(s) didn't match nodeSelector
# → Karpenter라면 arm64 노드를 프로비저닝 (NodePool이 arm64 허용 시)
```

**관찰** — Pod의 `nodeSelector`(08)가 Karpenter의 노드 선택을 좌우합니다. arm64를 요구하면 Karpenter는 arm64 노드를 만듭니다(NodePool requirements에 arm64가 있으면). 08의 어피니티·taint·토폴로지가 모두 노드 프로비저닝 결정에 들어갑니다.

## 4. requests가 없으면? (핵심 함정 미리보기)

```bash
# 리소스 요청이 없는 Pod
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: no-requests }
spec:
  containers:
    - name: app
      image: registry.k8s.io/pause:3.9
      # resources 없음 (requests 미설정)
EOF
```

**핵심 문제** — requests가 없으면 스케줄러는 이 Pod를 "0 리소스"로 보고 아무 노드에나 욱여넣습니다. Karpenter도 이 Pod가 얼마나 필요한지 몰라 **노드 크기를 잘못 계산**합니다 → 노드가 과부하되거나 통합이 오작동. 그래서 **requests 설정은 노드 오토스케일의 전제**입니다(pitfalls 1번). 08에서 배운 requests가 여기서 결정적입니다.

## 5. 정리

```bash
kubectl delete deploy hungry
kubectl delete pod arm-workload no-requests 2>/dev/null || true
```

## 정리

- 노드 오토스케일러의 트리거 = `Pending` Pod (`Insufficient cpu` 등)
- Karpenter는 Pending Pod 요구를 모아 **딱 맞는 노드를 계산**(빈패킹) — CA는 고정 노드그룹만
- 08의 스케줄 제약(requests·nodeSelector·affinity·taint)이 노드 선택을 좌우 — Karpenter는 스케줄링의 역방향
- **requests 미설정 = 노드 크기 오판** → 노드 오토스케일의 전제는 정확한 requests(08)
- **★ Pod 층 스케일(HPA·KEDA·Knative)이 Pending을 만들면, 노드 층(Karpenter)이 받아 완전한 탄력성**
