# Lab 01 — 스케줄링 사이클 관측

## Step 1. Filter 집계 메시지를 "플러그인 언어"로 읽기

여러 Filter를 동시에 위반하는 Pod를 만들어 메시지를 해부합니다:

```bash
NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
kubectl taint node ${NODES[0]} exam=filter:NoSchedule

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: multi-reject }
spec:
  nodeSelector: { no-such-label: "true" }
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sleep, "300"]
    resources: { requests: { cpu: "30" } }
EOF
sleep 5
kubectl describe pod multi-reject | grep -A 3 "Events" | tail -2
```

예상 출력 (환경에 따라 수치 다름):
```
FailedScheduling ... 0/2 nodes are available:
1 node(s) had untolerated taint {exam: filter},      ← TaintToleration
2 node(s) didn't match Pod's node affinity/selector,  ← NodeAffinity
2 Insufficient cpu.                                   ← NodeResourcesFit
preemption: 0/2 nodes are available: 2 No preemption victims found...  ← PostFilter도 실패
```

✅ 한 노드가 **여러 사유로 중복 집계**될 수 있고, 마지막 줄은 PostFilter(선점)까지 시도했다는 기록입니다. 이 메시지를 보고 "어느 플러그인 → 어느 YAML 필드"로 역추적하는 것이 스케줄링 디버깅의 전부.

```bash
kubectl delete pod multi-reject
kubectl taint node ${NODES[0]} exam=filter:NoSchedule-
```

## Step 2. backoff 큐 관찰 — "비웠는데 바로 안 들어가는" 시간

```bash
# 들어갈 수 없는 Pod (거대 cpu 요청)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: waiter
  labels: { run: waiter }
spec:
  containers:
    - name: waiter
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      resources:
        requests:
          cpu: 1500m
EOF
sleep 10
kubectl get events --field-selector involvedObject.name=waiter --sort-by=.lastTimestamp | tail -3
```

FailedScheduling이 **즉시 연속이 아니라 점점 간격을 벌리며** 기록됩니다 — backoffQ의 지수 백오프. 이제 자리를 만들어주면:

```bash
# 다른 워크로드가 없다면 노드에 자리가 있을 수 있으니, 이 실험은 "여유 확보 시점"과
# Pod가 Running 되는 시점의 시차(수 초)를 관찰하는 것으로 충분합니다.
kubectl delete pod waiter
```

## Step 3. nominatedNodeName — 선점의 흔적

모듈 12 lab-02의 선점 실험을 한 단계 깊게 — 선점 직후 아직 자리가 안 빈 동안:

```bash
kubectl get pod <선점한-pod> -o jsonpath='{.status.nominatedNodeName}'
```

선점을 발동한 Pod는 희생자가 비워줄 노드를 **예약 표시**(nominated)로 갖습니다 — "Pending인데 갈 곳은 정해진" 중간 상태. (모듈 12 실험을 재현할 때 확인해보세요)

## Step 4. 스케줄러의 자기 기록 — 이벤트의 출처 확인

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: placed
  labels: { run: placed }
spec:
  containers:
    - name: placed
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "60"]
EOF
sleep 5
kubectl get events --field-selector involvedObject.name=placed \
  -o custom-columns=SOURCE:.source.component,REASON:.reason,MSG:.message | head -3
```

예상:
```
SOURCE              REASON      MSG
default-scheduler   Scheduled   Successfully assigned default/placed to ip-...
```

✅ `default-scheduler`라는 SOURCE — lab-02에서 우리가 띄울 두 번째 스케줄러는 여기 **다른 이름**이 찍히게 됩니다.

## 정리

```bash
kubectl delete pod placed waiter multi-reject --ignore-not-found
```
