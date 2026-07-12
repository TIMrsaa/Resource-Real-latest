# Lab 01 — 파이프라인 관측: -v=8, conflict, watch

## Step 1. 요청 한 번을 와이어 레벨로

```bash
kubectl create deployment obs --image=public.ecr.aws/nginx/nginx:1.27 -v=8 2>&1 | grep -E "POST|Response Status|Request Body" | head -6
```

예상 출력 (발췌):
```
POST https://...eks.amazonaws.com/apis/apps/v1/namespaces/default/deployments
Request Body: {"kind":"Deployment", ...}
Response Status: 201 Created in 45 milliseconds
```

```bash
# 같은 요청을 권한 없는 신원으로 → 파이프라인 ②에서 차단
kubectl create deployment obs2 --image=nginx --as=nobody -v=8 2>&1 | grep "Response Status"
```

예상: `Response Status: 403 Forbidden ...` — **POST가 etcd에 닿기 전에 죽었습니다.** 401/403/422가 각각 파이프라인의 다른 단계임을 -v=8의 status로 식별하는 습관.

## Step 2. mutating의 흔적 찾기 — 내가 안 쓴 필드들

```bash
kubectl get deployment obs -o yaml | grep -E "creationTimestamp|resourceVersion|uid|strategy|progressDeadline|terminationGracePeriod" | head -8
```

예상: 제출한 적 없는 strategy(RollingUpdate 25%/25%), terminationGracePeriodSeconds(30) 등이 채워져 있습니다 — **③ 단계(기본값 주입 admission)의 작품.** "내 YAML과 클러스터의 YAML이 다른" 이유의 정체.

## Step 3. 409 Conflict 재현 — 낙관적 동시성

```bash
# 같은 rv의 사본을 두 개 받아둡니다
kubectl get deployment obs -o yaml > /tmp/copy-a.yaml
cp /tmp/copy-a.yaml /tmp/copy-b.yaml

# B 사본으로 먼저 수정 적용 (rv 일치 → 성공, rv 증가)
sed -i 's/replicas: 1/replicas: 2/' /tmp/copy-b.yaml
kubectl replace -f /tmp/copy-b.yaml

# A 사본(옛 rv)으로 수정 시도
sed -i 's/replicas: 1/replicas: 3/' /tmp/copy-a.yaml
kubectl replace -f /tmp/copy-a.yaml
```

예상 출력:
```
Error from server (Conflict): ... the object has been modified; please apply your changes to the latest version and try again
```

✅ **rv가 낡은 쓰기는 거부됩니다.** 해소법 비교:
- `kubectl replace` (전체 교체): rv 검사 — 방금처럼 충돌
- `kubectl apply`: 서버가 병합 — 대부분 통과
- `kubectl patch`: 부분 수정 — rv 무관 통과
- 컨트롤러 코드: 재시도 루프 (모듈 31)

## Step 4. watch 프로토콜 직접 보기

```bash
# 프록시로 API 서버를 localhost에 열고 curl로 raw watch
kubectl proxy --port=8001 &
PROXY_PID=$!
sleep 2
curl -N "http://localhost:8001/api/v1/namespaces/default/pods?watch=true" &
CURL_PID=$!
sleep 2
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: watch-me
  labels: { run: watch-me }
spec:
  containers:
    - name: watch-me
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "60"]
EOF
sleep 8
kill $CURL_PID $PROXY_PID
```

예상 출력 (curl 쪽에 실시간으로):
```
{"type":"ADDED","object":{"kind":"Pod","metadata":{"name":"watch-me",...
{"type":"MODIFIED","object":...   ← 스케줄러가 nodeName 채움
{"type":"MODIFIED","object":...   ← kubelet이 status 갱신
```

✅ `kubectl get -w`의 정체 = **끝나지 않는 HTTP 응답.** MODIFIED 이벤트들이 모듈 02에서 배운 "스케줄러→kubelet 릴레이"의 와이어 증거입니다.

## Step 5. resourceVersion과 410 Gone (개념 확인)

```bash
# 아주 옛날 rv로 watch를 걸면?
curl -s "http://localhost:8001/api/v1/pods?watch=true&resourceVersion=1" 2>/dev/null | head -1
```

(프록시 다시 켜고 시도) 예상: `{"type":"ERROR","object":{"kind":"Status","code":410,...}` — too old. 컨트롤러/informer가 이때 **전체 relist**를 합니다 — 대규모 클러스터에서 relist 폭풍이 API 부하 사고가 되는 배경(모듈 37).

## 정리

```bash
kubectl delete deployment obs --ignore-not-found
kubectl delete pod watch-me --ignore-not-found
rm -f /tmp/copy-a.yaml /tmp/copy-b.yaml
```
