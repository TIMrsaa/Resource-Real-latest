# Lab 01 — ConfigMap 주입 2방식과 실시간 갱신 실험

## Step 1. 배포 및 두 방식 확인

```bash
kubectl apply -f manifests/config-demo.yaml
kubectl wait --for=condition=Ready pod -l app=config-demo

POD=$(kubectl get pod -l app=config-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- env | grep -E "GREETING"
kubectl exec $POD -- ls /etc/config
kubectl exec $POD -- cat /etc/config/app.properties
```

예상 출력:
```
GREETING=hello                  ← 환경변수 주입
GREETING                        ← 파일로도 (key가 파일명)
app.properties
color=blue
mode=normal
```

> 💡 `app.properties`도 환경변수에 들어갔을까요? `env | grep app` — **있긴 한데** 줄바꿈 포함 멀티라인 env라 보통 쓸모없습니다. 파일형 데이터는 볼륨으로 쓰라는 신호.

## Step 2. 갱신 실험 — 이 모듈의 하이라이트

```bash
# ConfigMap 수정
kubectl patch configmap app-config --type=merge \
  -p '{"data":{"GREETING":"bonjour","app.properties":"color=red\nmode=turbo\n"}}'

# 환경변수: 영원히 안 바뀜
kubectl exec $POD -- sh -c 'echo "env: $GREETING"'

# 파일: 최대 1분쯤 기다리며 반복 확인
for i in $(seq 1 12); do
  kubectl exec $POD -- cat /etc/config/app.properties | head -1
  sleep 10
done
```

예상 출력:
```
env: hello            ← 환경변수는 옛값 그대로!
color=blue
color=blue
color=red             ← 어느 순간 파일이 바뀝니다 (재시작 없이!)
```

✅ **검증 포인트**: 같은 ConfigMap인데 환경변수는 고정, 파일은 자동 갱신. RESTARTS도 0 그대로(`kubectl get pod`)입니다. — "설정 바꿨는데 왜 적용이 안 돼요?"의 절반은 환경변수 주입 + 재시작 누락입니다.

```bash
# 갱신의 트릭 구경: 심볼릭 링크 원자 교체
kubectl exec $POD -- ls -la /etc/config/
```

예상 출력 (발췌):
```
lrwxrwxrwx  ..data -> ..2026_06_10_12_34_56.123/   ← 타임스탬프 디렉터리로 링크 교체
lrwxrwxrwx  app.properties -> ..data/app.properties
```

## Step 3. 환경변수를 갱신하는 공식 방법

```bash
kubectl rollout restart deployment config-demo
kubectl wait --for=condition=Ready pod -l app=config-demo
POD=$(kubectl get pod -l app=config-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- sh -c 'echo "env: $GREETING"'
# → env: bonjour
```

## Step 4. 없는 ConfigMap을 참조하면?

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: missing-ref
  labels: { run: missing-ref }
spec:
  containers:
    - name: missing-ref
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
      envFrom:
        - configMapRef: { name: no-such-config }
EOF
sleep 5; kubectl get pod missing-ref; kubectl describe pod missing-ref | tail -3
```

예상:
```
missing-ref   0/1   CreateContainerConfigError
Warning  Failed  ... configmap "no-such-config" not found
```

✅ ConfigMap 누락은 **컨테이너 생성 단계 에러**로 나타납니다 — 모듈 02의 "체인 어디가 끊겼나" 표에 한 줄 추가된 것.

```bash
kubectl delete pod missing-ref
```

## Step 5. immutable 체험

```bash
kubectl patch configmap app-config --type=merge -p '{"immutable":true}'
kubectl patch configmap app-config --type=merge -p '{"data":{"GREETING":"hola"}}'
```

예상 출력:
```
The ConfigMap "app-config" is invalid: data: Forbidden: field is immutable when `immutable` is set
```

✅ 잠겼습니다. 풀 방법은 삭제 후 재생성뿐 — 운영에서 "이름에 해시 + 새 이름으로 교체" 패턴을 쓰는 이유.

## 정리

config-demo는 lab-02에서 계속 사용. 그대로 두기.
