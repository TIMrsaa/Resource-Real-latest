# Lab 02 — Pod 생성 한 번의 전체 여정 추적

> **목표**: `kubectl run` 한 줄이 일으키는 이벤트 체인을 컴포넌트별로 추적합니다.
> 이 추적 능력이 곧 K8s 디버깅 능력입니다. **이 커리큘럼에서 가장 중요한 실습.**

## 우리가 추적할 체인

```
kubectl ─① POST→ API서버 ─② 저장→ etcd
                   │
   스케줄러 ─③ watch: "nodeName 빈 Pod 발견" → ④ binding 기록
                   │
   kubelet ─⑤ watch: "내 노드에 배정됨" → ⑥ CNI(IP) + containerd(컨테이너)
                   │
           ─⑦ status 보고 → Running
```

## Step 1. 이벤트 감시 준비

터미널 1:
```bash
kubectl get events -w --field-selector involvedObject.name=trace-me
```

## Step 2. Pod 생성 (터미널 2)

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: trace-me
  labels: { run: trace-me }
spec:
  containers:
    - name: trace-me
      image: public.ecr.aws/nginx/nginx:latest
EOF
```

터미널 1 예상 출력 — **이 순서가 곧 아키텍처입니다**:
```
LAST SEEN  TYPE    REASON     OBJECT        MESSAGE
0s         Normal  Scheduled  pod/trace-me  Successfully assigned default/trace-me to ip-192-168-xx-xx...   ← ③④ 스케줄러
0s         Normal  Pulling    pod/trace-me  Pulling image "public.ecr.aws/nginx/nginx:latest"               ← ⑥ kubelet
2s         Normal  Pulled     pod/trace-me  Successfully pulled image ...
2s         Normal  Created    pod/trace-me  Created container: trace-me                                     ← ⑥ containerd
2s         Normal  Started    pod/trace-me  Started container trace-me                                      ← ⑦
```

✅ **검증 포인트**: 첫 이벤트의 주체는 `default-scheduler`, 나머지는 `kubelet`입니다. 확인:

```bash
kubectl get events --field-selector involvedObject.name=trace-me \
  -o custom-columns=REASON:.reason,SOURCE:.source.component,MESSAGE:.message
```

## Step 3. 스케줄러의 흔적 — nodeName

```bash
# 생성 직후의 Pod에는 nodeName이 없었습니다. 지금은:
kubectl get pod trace-me -o jsonpath='{.spec.nodeName}{"\n"}'
```

예상 출력:
```
ip-192-168-xx-xx.ap-northeast-2.compute.internal
```

스케줄러가 한 일의 전부가 이 필드 하나를 채운 것입니다.

## Step 4. CNI의 흔적 — Pod IP

```bash
kubectl get pod trace-me -o jsonpath='{.status.podIP}{"\n"}'
```

예상 출력 (VPC의 실제 사설 IP!):
```
192.168.x.x
```

> EKS의 특징: Pod IP가 VPC IP 대역에서 직접 나옵니다(VPC CNI). 다른 CNI는 오버레이 대역을 쓰기도 합니다 — eks 파트 07에서 심층.

## Step 5. status 섹션 정독 — kubelet의 보고서

```bash
kubectl get pod trace-me -o yaml | grep -A 30 "^status:"
```

예상 출력에서 볼 것:
```
status:
  conditions:              ← PodScheduled / Initialized / ContainersReady / Ready
  - type: PodScheduled
    status: "True"
  containerStatuses:
  - containerID: containerd://...    ← 런타임이 containerd라는 증거
    image: ...
    state:
      running:
        startedAt: ...
  hostIP: 192.168.y.y      ← 노드 IP
  podIP: 192.168.x.x       ← Pod IP
  qosClass: BestEffort
```

✅ `spec`은 내가 쓴 주문서, `status`는 kubelet이 채운 보고서 — 같은 객체 안에 공존합니다.

## Step 6. 장애를 일부러 만들어 체인 끊어보기

### 6-1. 스케줄링 실패 (③에서 멈춤)

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: too-big
  labels: { run: too-big }
spec:
  containers:
    - name: too-big
      image: public.ecr.aws/nginx/nginx:latest
      resources:
        requests:
          cpu: "100"          # 100 코어 — 어떤 노드도 만족 못 하는 요구
EOF
kubectl get pod too-big
```

예상 출력:
```
NAME      READY   STATUS    RESTARTS   AGE
too-big   0/1     Pending   0          10s     ← 영원히 Pending
```

```bash
kubectl describe pod too-big | tail -5
```

예상:
```
Warning  FailedScheduling  ...  0/2 nodes are available: 2 Insufficient cpu. ...
```

✅ **CPU 100개를 줄 노드가 없어서 스케줄러 단계(③)에서 멈췄습니다.** `Pending` = "스케줄러 또는 그 이전 문제"라는 공식을 얻었습니다.

### 6-2. 이미지 풀 실패 (⑥에서 멈춤)

```bash
kubectl run bad-image --image=this-image-does-not-exist-xyz
sleep 15 && kubectl get pod bad-image
```

예상 출력:
```
NAME        READY   STATUS             RESTARTS   AGE
bad-image   0/1     ErrImagePull       0          15s    (또는 ImagePullBackOff)
```

✅ 스케줄링은 됐고(nodeName 있음) kubelet의 이미지 풀(⑥)에서 실패. **상태 이름만 보고 "체인의 어디가 끊겼는지" 즉답**할 수 있게 됐습니다:

| 상태 | 끊긴 지점 |
|------|----------|
| Pending (이벤트 FailedScheduling) | ③ 스케줄러 — 자원/제약 |
| ErrImagePull / ImagePullBackOff | ⑥ kubelet — 이미지 이름/권한 |
| ContainerCreating에서 정지 | ⑥ CNI/볼륨 마운트 |
| CrashLoopBackOff | 컨테이너는 떴는데 **앱이** 계속 죽음 |

## 정리

```bash
kubectl delete pod trace-me too-big bad-image
```

## 다음

Pod의 내부 구조(컨테이너 여러 개, init, pause)는 [모듈 03](../03-pod/)에서.
