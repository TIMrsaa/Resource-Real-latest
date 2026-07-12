# Lab 01 — crictl: kubelet의 눈으로 노드 보기

## Step 0. 관찰 대상 Pod + 노드 진입

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: target
  labels: { app: target }
spec:
  replicas: 1
  selector:
    matchLabels: { app: target }
  template:
    metadata:
      labels: { app: target }
    spec:
      containers:
        - name: target
          image: public.ecr.aws/nginx/nginx:1.27
EOF
kubectl wait --for=condition=Available deploy/target
NODE=$(kubectl get pod -l app=target -o jsonpath='{.items[0].spec.nodeName}')
POD_UID=$(kubectl get pod -l app=target -o jsonpath='{.items[0].metadata.uid}')
echo "node=$NODE uid=$POD_UID"

kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable
```

(이하 노드 디버그 셸 안에서 — `chroot /host` 먼저)

```sh
chroot /host
```

## Step 1. sandbox(=pause)와 컨테이너 구분해 보기

```sh
crictl pods --name target | head -3
POD_ID=$(crictl pods --name target -q | head -1)
crictl ps --pod $POD_ID
```

예상 출력:
```
POD ID       NAME            NAMESPACE   STATE
1a2b3c...    target-xxx-yyy  default     Ready        ← sandbox (Pod 단위)
CONTAINER    NAME    STATE     POD ID
9f8e7d...    nginx   Running   1a2b3c...               ← 그 안의 컨테이너
```

✅ CRI 세계에서 Pod = sandbox, 컨테이너는 그 소속입니다 — RunPodSandbox가 먼저인 이유의 시각화.

## Step 2. sandbox 상세 — CNI의 결과물 확인

```sh
crictl inspectp $POD_ID | grep -A3 '"ip"'
```

예상: Pod IP가 sandbox 레벨에 기록되어 있습니다 (컨테이너가 아니라!) — IP는 pause의 NET namespace 소유라는 모듈 03의 증거가 CRI 데이터에도.

## Step 3. ImageService 체험

```sh
crictl images | head -8
crictl pull public.ecr.aws/docker/library/redis:7-alpine     # kubelet이 하는 그 호출
crictl images | grep redis
crictl rmi public.ecr.aws/docker/library/redis:7-alpine
```

✅ `PullImage`를 손으로 — Pod 생성 타임라인 3단계를 단독 실행한 것.

## Step 4. 컨테이너 죽이고 kubelet의 복구 관찰

```sh
CID=$(crictl ps --pod $POD_ID -q)
crictl stop $CID && crictl rm $CID
sleep 5
crictl ps --pod $POD_ID
```

예상: **새 컨테이너 ID**가 떠 있습니다! kubelet의 조정 루프(PLEG가 죽음 감지 → SyncPod가 재생성)가 작동한 것. 다른 터미널에서:

```bash
kubectl get pod -l app=target    # RESTARTS 1 증가, Pod 이름/IP는 그대로
```

✅ **"kubelet도 컨트롤러다"의 실증** — 우리가 런타임 레벨에서 지웠는데 선언 상태(이 Pod에 nginx 1개)로 되돌렸습니다. sandbox는 안 죽였으므로 IP 불변(모듈 03 Step 5와 같은 원리, 이번엔 CRI 레벨에서).

## Step 5. kubelet 로그에서 방금 일을 찾아보기

```sh
journalctl -u kubelet --since "5 min ago" --no-pager | grep -iE "target|restart|backoff" | tail -5
```

예상: 컨테이너 사망 감지와 재시작 결정 기록. `journalctl -u kubelet`은 ContainerCreating 멈춤/볼륨 마운트 실패 디버깅의 최종 병기입니다.

## Step 6. exec의 경로 확인 (개념)

`kubectl exec`의 실제 경로: kubectl → API 서버 → **kubelet(10250 포트)** → CRI ExecSync → 컨테이너. API 서버가 중계하므로 노드에 SSH가 없어도 되는 것이고, RBAC의 `pods/exec`(모듈 11)이 이 경로의 관문입니다.

```sh
exit; exit   # chroot와 디버그 Pod에서 나가기
```

## 정리

```bash
kubectl delete deployment target
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
```
