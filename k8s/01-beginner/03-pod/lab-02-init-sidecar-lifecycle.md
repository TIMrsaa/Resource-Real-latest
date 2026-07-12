# Lab 02 — init/sidecar 시작 순서와 종료 시퀀스

## Step 1. 시작 순서 타임라인 관찰

터미널 1 (감시):
```bash
kubectl get pods -w
```

터미널 2 (생성):
```bash
kubectl apply -f manifests/init-sidecar-pod.yaml
```

터미널 1 예상 출력 (타임라인):
```
startup-order   0/2     Pending           0      0s
startup-order   0/2     Init:0/2          0      1s    ← step1-init 실행 중
startup-order   0/2     Init:1/2          0      6s    ← step1 끝(5초 걸림), step2(sidecar) 시작
startup-order   0/2     PodInitializing   0      7s
startup-order   2/2     Running           0      8s    ← READY 2/2: sidecar + app
```

✅ **검증 포인트**:
- `Init:0/2 → Init:1/2` — init은 **순서대로 하나씩**
- 최종 READY가 **2/2** — sidecar는 init 자리에 선언했지만 **계속 살아서** 카운트에 포함됩니다 (일반 init이었다면 1/1)

```bash
# 각 컨테이너 로그로 순서 재확인
kubectl logs startup-order -c step1-init
kubectl logs startup-order -c step2-sidecar
kubectl logs startup-order -c step3-app
```

## Step 2. sidecar에서 restartPolicy 한 줄 빼보기 (반례 실험)

`manifests/init-sidecar-pod.yaml`에서 `restartPolicy: Always` 줄을 주석 처리하고:

```bash
kubectl delete pod startup-order
kubectl apply -f manifests/init-sidecar-pod.yaml
kubectl get pod startup-order -w
```

예상: `Init:1/2` 에서 **영원히 멈춥니다.** 일반 init 컨테이너는 "종료되어야" 다음으로 넘어가는데, step2는 무한 sleep이라 안 끝나기 때문. 이 한 줄의 의미를 체감했으면 주석을 원복하세요.

## Step 3. 종료 시퀀스 — SIGTERM과 유예 시간

```bash
# SIGTERM을 무시하는 고집쟁이 Pod
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: stubborn
  labels: { run: stubborn }
spec:
  terminationGracePeriodSeconds: 10
  containers:
    - name: stubborn
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sh", "-c", 'trap "echo got SIGTERM but ignoring" TERM; while true; do sleep 1; done']
EOF
kubectl wait --for=condition=Ready pod/stubborn

# 삭제하면서 시간 측정
time kubectl delete pod stubborn
```

예상 출력:
```
pod "stubborn" deleted
real    0m12.x s     ← 약 10초+α: SIGTERM 무시 → 유예 10초 → SIGKILL
```

✅ **검증 포인트**: 삭제가 즉시가 아니라 **terminationGracePeriodSeconds만큼 걸렸습니다**. 앱이 SIGTERM을 제대로 처리하면 1~2초에 끝납니다. "배포할 때마다 504 에러가 잠깐 난다"는 실무 문제의 뿌리가 여기입니다 (모듈 14에서 해결).

## Step 4. CrashLoopBackOff 만들기 — 백오프 직접 관찰

```bash
kubectl run crasher --image=public.ecr.aws/docker/library/busybox:stable -- sh -c 'echo died; exit 1'
kubectl get pod crasher -w
```

예상 출력 (시간을 두고):
```
crasher   0/1     Error              1 (5s ago)    8s
crasher   0/1     CrashLoopBackOff   1 (6s ago)    9s
crasher   0/1     Error              2 (3s ago)    25s     ← 재시작 간격이 점점 벌어짐
crasher   0/1     CrashLoopBackOff   2 (4s ago)    26s
```

```bash
kubectl describe pod crasher | grep -A 3 "Last State"
```

예상:
```
Last State:  Terminated
  Reason:    Error
  Exit Code: 1          ← 앱이 1로 종료했다는 기록
```

✅ CrashLoopBackOff의 정체 = "재시작 → 또 죽음 → 백오프 대기"의 반복. 디버깅 1순위는 `kubectl logs crasher --previous` (죽기 전 로그).

## 정리

```bash
kubectl delete pod startup-order crasher --ignore-not-found
```
