# Lab 02 — Topology Spread와 Priority/Preemption

## Step 1. AZ 분산 검증

> 노드그룹이 멀티 AZ에 걸쳐 있어야 합니다. `kubectl get nodes -L topology.kubernetes.io/zone`으로 AZ가 2개 이상인지 확인. (1개라면 hostname 단위로 실습해도 원리는 동일)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: spread-demo }
spec:
  replicas: 4
  selector: { matchLabels: { app: spread-demo } }
  template:
    metadata: { labels: { app: spread-demo } }
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector: { matchLabels: { app: spread-demo } }
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname        # 노드 단위로도 분산
        whenUnsatisfiable: ScheduleAnyway          # soft
        labelSelector: { matchLabels: { app: spread-demo } }
      containers:
      - { name: c, image: public.ecr.aws/docker/library/busybox:stable, command: [sleep, "3600"],
          resources: { requests: { cpu: 10m } } }
EOF
sleep 10
kubectl get pods -l app=spread-demo -o wide | awk 'NR>1{print $7}' | sort | uniq -c
```

예상 출력 (노드 2대 기준):
```
   2 ip-...-aaa...
   2 ip-...-bbb...      ← 2:2 균등 (maxSkew=1이라 3:1은 불허)
```

✅ AZ/노드 장애가 나도 절반은 삽니다 — **고가용성은 replicas 숫자가 아니라 분포가 만듭니다.**

## Step 2. 일부러 어기기 — DoNotSchedule의 강제력

```bash
# 한 노드를 cordon(신규 배치 차단)하고 replicas를 늘리면?
NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
kubectl cordon ${NODES[1]}
kubectl scale deployment spread-demo --replicas=8
sleep 10; kubectl get pods -l app=spread-demo | grep -c Pending
```

예상: 일부가 **Pending** — 한쪽 zone/노드에만 더 태우면 maxSkew를 어기므로 차라리 안 태웁니다. describe에서 메시지 확인:

```bash
kubectl describe pod $(kubectl get pods -l app=spread-demo --field-selector status.phase=Pending -o jsonpath='{.items[0].metadata.name}') | tail -3
# → ... didn't match pod topology spread constraints
kubectl uncordon ${NODES[1]}; kubectl scale deployment spread-demo --replicas=4
```

> 💡 트레이드오프 체감: DoNotSchedule(분포 보장, 가용량 부족 시 Pending) vs ScheduleAnyway(배치 보장, 분포는 최선 노력). 서비스 성격에 따라 고르는 것이지 정답이 있지 않습니다.

## Step 3. PriorityClass — 중요한 것이 이깁니다

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: vip }
value: 100000
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: peasant }
value: 100
EOF

# 클러스터를 낮은 우선순위 Pod로 꽉 채웁니다 (노드 가용 CPU에 맞게 조정)
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: filler
  labels: { app: filler }
spec:
  replicas: 2
  selector:
    matchLabels: { app: filler }
  template:
    metadata:
      labels: { app: filler }
    spec:
      priorityClassName: peasant           # 낮은 우선순위 — 선점당할 운명
      containers:
        - name: filler
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sleep", "3600"]
          resources:
            requests: { cpu: 1200m }       # 노드 CPU를 채우는 크기 (환경에 맞게 조정)
EOF
kubectl rollout status deploy/filler --timeout=120s
kubectl get pods -l app=filler -o wide
```

(t3.medium 2대 기준 CPU가 거의 찬 상태가 됩니다. filler가 Pending이면 cpu를 900m 등으로 낮춰 재시도)

```bash
# VIP Pod 등장 — 자리가 없습니다!
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: vip
  labels: { run: vip }
spec:
  priorityClassName: vip
  containers:
    - name: vip
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "3600"]
      resources:
        requests:
          cpu: 1000m
EOF
kubectl get pods -w
```

예상 출력 (수십 초 내):
```
filler-...   1/1   Terminating    ← 낮은 우선순위가 쫓겨남 (선점!)
vip          0/1   Pending
vip          1/1   Running        ← 그 자리에 VIP 입장
```

```bash
kubectl get events --sort-by=.lastTimestamp | grep -i preempt | tail -2
# → ... Preempted by pod ... on node ...
```

✅ **선점(preemption)을 직접 목격.** 결제/알림 같은 핵심 서비스가 배치 작업에 밀려 Pending이 되는 일을 막는 장치입니다. 쫓겨난 filler는 RS가 계속 재시도합니다(자리 나면 복귀) — 조정 루프는 여기서도.

## 정리

```bash
bash cleanup.sh
```
