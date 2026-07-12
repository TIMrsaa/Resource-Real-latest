# Lab 01 — 임시 볼륨의 수명 실험

## Step 1. emptyDir — 컨테이너 재시작에는 생존

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: scratch
spec:
  volumes:
  - name: tmp
    emptyDir: {}
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:stable
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts: [{ name: tmp, mountPath: /scratch }]
EOF
kubectl wait --for=condition=Ready pod/scratch

kubectl exec scratch -- sh -c 'echo "important data" > /scratch/file.txt'
kubectl exec scratch -- kill 1            # 컨테이너 재시작 유발
sleep 5
kubectl exec scratch -- cat /scratch/file.txt
```

예상 출력:
```
important data       ← 살아있습니다! (RESTARTS는 1)
```

✅ emptyDir의 수명 = **Pod**. 컨테이너의 쓰기 레이어(모듈 01 — 재시작 시 소멸)와 다른 점.

## Step 2. emptyDir — Pod 삭제에는 소멸

```bash
kubectl delete pod scratch
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: scratch
spec:
  volumes: [{ name: tmp, emptyDir: {} }]
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:stable
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts: [{ name: tmp, mountPath: /scratch }]
EOF
kubectl wait --for=condition=Ready pod/scratch
kubectl exec scratch -- ls /scratch/
```

예상 출력: (빈 출력) — 같은 이름의 Pod라도 **새 Pod = 새 emptyDir**.

## Step 3. hostPath — 노드에 묶인 데이터

```bash
kubectl delete pod scratch
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: hp-writer
spec:
  volumes:
  - name: hostdir
    hostPath: { path: /tmp/lab-hostpath, type: DirectoryOrCreate }
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:stable
    command: ["sh", "-c", "echo written-by-$NODE > /hostdir/who.txt; sleep 3600"]
    env:
    - { name: NODE, valueFrom: { fieldRef: { fieldPath: spec.nodeName } } }
    volumeMounts: [{ name: hostdir, mountPath: /hostdir }]
EOF
kubectl wait --for=condition=Ready pod/hp-writer
kubectl get pod hp-writer -o jsonpath='{.spec.nodeName}{"\n"}'
kubectl exec hp-writer -- cat /hostdir/who.txt
```

예상 출력:
```
ip-192-168-xx-xx....
written-by-ip-192-168-xx-xx...
```

이제 Pod를 지우고 다시 만들면? **다른 노드에 뜰 수 있고**, 그러면 /tmp/lab-hostpath는 빈 디렉터리입니다. 데이터가 "노드 복권"에 달려 있는 것 — 앱 데이터에 hostPath를 쓰면 안 되는 이유입니다.

```bash
kubectl delete pod hp-writer
```

## Step 4. 그래서 무엇이 필요한가

"Pod가 어느 노드에 가든, 몇 번을 다시 태어나든 따라다니는 디스크" — 그것이 PV/PVC입니다. lab-02로.

## 정리

```bash
kubectl delete pod scratch hp-writer --ignore-not-found
```
