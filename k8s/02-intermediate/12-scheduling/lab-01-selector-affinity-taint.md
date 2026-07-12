# Lab 01 — nodeSelector, affinity, taint/toleration

## Step 0. 노드에 실험용 라벨 부여

```bash
NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
kubectl label node ${NODES[0]} disktype=ssd
kubectl label node ${NODES[1]} disktype=hdd
kubectl get nodes -L disktype,topology.kubernetes.io/zone
```

예상 출력: 노드별 disktype과 AZ 라벨 확인.

## Step 1. nodeSelector

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: on-ssd
  labels: { run: on-ssd }
spec:
  nodeSelector: { disktype: ssd }
  containers:
    - name: on-ssd
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "3600"]
EOF
kubectl get pod on-ssd -o wide
```

✅ NODE 열이 ${NODES[0]}입니다. 반대 실험 — 없는 라벨을 요구하면:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: on-nvme
  labels: { run: on-nvme }
spec:
  nodeSelector: { disktype: nvme }
  containers:
    - name: on-nvme
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "3600"]
EOF
kubectl get pod on-nvme; kubectl describe pod on-nvme | tail -3
```

예상:
```
on-nvme   0/1   Pending
Warning  FailedScheduling ... 0/2 nodes are available: 2 node(s) didn't match Pod's node affinity/selector
```

✅ required류의 실패 모드 = **Pending.** 이 메시지를 정확히 읽는 것이 스케줄링 디버깅의 90%.

## Step 2. nodeAffinity — preferred의 "되면 좋고"

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: prefer-ssd }
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - { key: disktype, operator: In, values: [nvme] }   # 존재하지 않는 조건!
  containers:
  - { name: c, image: public.ecr.aws/docker/library/busybox:stable, command: [sleep, "3600"] }
EOF
kubectl get pod prefer-ssd -o wide
```

✅ nvme 노드가 없는데도 **Running** — preferred는 못 맞춰도 스케줄됩니다. Step 1의 Pending과 대조.

## Step 3. taint — 노드의 출입금지

```bash
kubectl taint node ${NODES[0]} team=ml:NoSchedule

# toleration 없는 Pod들 → 전부 다른 노드로 갈 수밖에
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crowd
  labels: { app: crowd }
spec:
  replicas: 4
  selector:
    matchLabels: { app: crowd }
  template:
    metadata:
      labels: { app: crowd }
    spec:
      containers:
        - name: crowd
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sleep", "3600"]
EOF
sleep 10; kubectl get pods -l app=crowd -o wide | awk '{print $7}' | sort | uniq -c
```

예상 출력:
```
   4 ip-...-NODES[1]...      ← taint 없는 노드에만 몰림
```

## Step 4. toleration = 입장권 (지정석 아님!)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: ml-job }
spec:
  replicas: 4
  selector: { matchLabels: { app: ml-job } }
  template:
    metadata: { labels: { app: ml-job } }
    spec:
      tolerations:
      - { key: team, operator: Equal, value: ml, effect: NoSchedule }
      containers:
      - { name: c, image: public.ecr.aws/docker/library/busybox:stable, command: [sleep, "3600"] }
EOF
sleep 10; kubectl get pods -l app=ml-job -o wide | awk 'NR>1{print $7}' | sort | uniq -c
```

예상 출력 (포인트!):
```
   2 ip-...-NODES[0]...      ← taint 노드에도 가고
   2 ip-...-NODES[1]...      ← 일반 노드에도 갑니다!
```

✅ **toleration만으론 "전용 배치"가 안 됩니다.** 완성하려면 nodeAffinity 추가:

```bash
kubectl patch deployment ml-job --type=json -p='[{"op":"add","path":"/spec/template/spec/affinity","value":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"disktype","operator":"In","values":["ssd"]}]}]}}}}]'
kubectl rollout status deploy/ml-job
kubectl get pods -l app=ml-job -o wide | awk 'NR>1{print $7}' | sort | uniq -c
```

예상: 4개 전부 NODES[0]. **taint(남들 차단) + affinity(우리는 거기로)** 콤보 완성 — GPU 노드 운영의 표준 공식.

## Step 5. NoExecute — 축출 관찰

```bash
kubectl taint node ${NODES[1]} evacuate=now:NoExecute
kubectl get pods -o wide -w     # NODES[1]에 있던 toleration 없는 Pod들이 Terminating → 다른 노드 재생성
```

(관찰 후 Ctrl+C)

```bash
kubectl taint node ${NODES[1]} evacuate=now:NoExecute-    # 해제 잊지 말기!
```

✅ NoExecute = 기존 Pod까지 쫓아냄. 노드 유지보수 전 비우기(drain)의 저수준 메커니즘입니다 (drain은 모듈 35).

## 정리

```bash
kubectl delete deployment crowd ml-job --ignore-not-found
kubectl delete pod on-ssd on-nvme prefer-ssd --ignore-not-found
kubectl taint node ${NODES[0]} team=ml:NoSchedule- 2>/dev/null || true
# 노드 라벨은 lab-02에서 사용하므로 유지
```
