# Lab 02 — QoS 클래스, Eviction, static Pod

## Step 1. QoS 3종 만들고 분류 확인

```bash
kubectl apply -f - <<'EOF'
# Guaranteed: requests == limits
apiVersion: v1
kind: Pod
metadata:
  name: qos-g
  labels: { run: qos-g }
spec:
  containers:
    - name: c
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      resources:
        requests: { cpu: 100m, memory: 64Mi }
        limits: { cpu: 100m, memory: 64Mi }
---
# Burstable: requests < limits
apiVersion: v1
kind: Pod
metadata:
  name: qos-b
  labels: { run: qos-b }
spec:
  containers:
    - name: c
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      resources:
        requests: { memory: 32Mi }
        limits: { memory: 128Mi }
---
# BestEffort: resources 없음
apiVersion: v1
kind: Pod
metadata:
  name: qos-be
  labels: { run: qos-be }
spec:
  containers:
    - name: c
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
EOF

kubectl get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass | grep qos-
```

예상 출력:
```
qos-g    Guaranteed
qos-b    Burstable
qos-be   BestEffort
```

✅ 내가 적은 requests/limits 조합이 **eviction 생존 순위표**로 변환됐습니다.

## Step 2. eviction 임계와 노드 컨디션 보기

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl describe node $NODE | grep -A 6 "Conditions:" | head -8
kubectl describe node $NODE | grep -A 8 "Allocated resources"
```

예상: MemoryPressure/DiskPressure = False (평시). 압박이 True가 되면 — kubelet이 eviction을 시작하고, 스케줄러도 taint(`node.kubernetes.io/memory-pressure`)로 신규 배치를 차단합니다. **taint(모듈 12) + eviction(이 모듈)이 연동되는 지점.**

> ⚠️ 실제 eviction 재현은 공유 노드 전체를 위험에 빠뜨리므로 하지 않습니다. 대신 아래 "관찰 시나리오"를 읽어두라:
> 노드 메모리가 임계 미달 → `Warning Evicted ... The node was low on resource: memory` 이벤트 + Pod status `Evicted` → BestEffort부터 사라짐. **Evicted Pod는 재시작이 아니라 시체로 남습니다** (Deployment라면 RS가 다른 노드에 새로 만듭니다).

## Step 3. OOMKilled와 Evicted를 구분하는 눈

```bash
# cgroup 한도 초과 = OOMKilled (커널 소행) — 안전하게 재현 가능 (자기 한도만 초과)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: oom-me
  labels: { run: oom-me }
spec:
  containers:
    - name: c
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sh", "-c", "head -c 100m /dev/zero | tail"]
      resources:
        limits: { memory: 50Mi }
EOF
sleep 15
kubectl get pod oom-me -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'; echo
```

예상 출력:
```
OOMKilled        ← 커널이 "이 컨테이너"를 처형 (limits 위반)
```

| | OOMKilled | Evicted |
|---|---|---|
| 집행자 | 커널 (cgroup) | kubelet |
| 이유 | **내** limits 초과 | **노드** 자원 부족 |
| 단위 | 컨테이너 | Pod |
| 대응 | limits/메모리 누수 점검 | requests 정직화, 노드 증설 |

## Step 4. static Pod — 파일이 곧 Pod

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable
```

노드 셸에서:
```sh
chroot /host
# kubelet 설정에서 staticPodPath 확인
grep -r staticPodPath /etc/kubernetes/kubelet/ 2>/dev/null || echo "staticPodPath 미설정(EKS 기본)"
# 설정돼 있다면 (또는 직접 지정해보는 개념 실습):
mkdir -p /etc/kubernetes/manifests
cat > /etc/kubernetes/manifests/static-hello.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: static-hello }
spec:
  containers:
  - name: hello
    image: public.ecr.aws/docker/library/busybox:stable
    command: ["sh", "-c", "sleep 3600"]
EOF
exit; exit
```

> EKS AL2023 노드는 기본적으로 staticPodPath가 비활성일 수 있습니다 — 그 경우 이 단계는 "kubeadm/kind에서는 이렇게 된다"는 개념 확인으로 충분합니다. kind(기여자 트랙 41)에서는 `docker exec kind-control-plane ls /etc/kubernetes/manifests`로 **apiserver/etcd 자체가 static Pod**임을 직접 보게 됩니다.

```bash
# staticPodPath가 활성인 환경이라면:
kubectl get pod static-hello-$NODE    # mirror Pod (이름에 노드명 접미사!)
kubectl delete pod static-hello-$NODE && sleep 5
kubectl get pod static-hello-$NODE    # → 부활! (진실은 파일이므로)
```

## 정리

```bash
bash cleanup.sh
```
