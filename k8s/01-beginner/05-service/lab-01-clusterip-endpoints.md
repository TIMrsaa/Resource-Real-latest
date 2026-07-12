# Lab 01 — ClusterIP와 연결 사슬, 그리고 3가지 고장 재현

## Step 1. 배포와 기본 확인

```bash
kubectl apply -f manifests/app-and-services.yaml
kubectl get deploy,svc,endpointslices -l app=echo 2>/dev/null; kubectl get endpointslices
```

예상 출력 (발췌):
```
service/echo   ClusterIP   172.20.xx.xx   <none>   80/TCP
NAME         ADDRESSTYPE   PORTS   ENDPOINTS
echo-xxxxx   IPv4          8080    192.168.a.a,192.168.b.b,192.168.c.c   ← Pod 3개의 실제 IP
```

✅ 연결 사슬 완성: Service(172.20.x.x) → EndpointSlice(Pod IP 3개) 확인.

## Step 2. 클러스터 안에서 호출 + 분배 관찰

```bash
# 임시 클라이언트 Pod에서 Service 이름으로 10번 호출
kubectl run client --rm -it --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  sh -c 'for i in $(seq 1 10); do wget -qO- http://echo/hostname; echo; done'
```

예상 출력 (Pod 이름이 섞여서 나옴):
```
echo-5d8f7c6b9-aaaaa
echo-5d8f7c6b9-ccccc
echo-5d8f7c6b9-aaaaa
echo-5d8f7c6b9-bbbbb
...
```

✅ **검증 포인트 2개**: ① `http://echo` — DNS 이름으로 호출됨 ② 응답 호스트가 골고루 섞임(분배). 정확히 균등하지 않은 것도 정상(무작위 분배).

## Step 3. ClusterIP는 "가짜 IP"다

```bash
SVC_IP=$(kubectl get svc echo -o jsonpath='{.spec.clusterIP}')
kubectl run pinger --rm -it --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  sh -c "ping -c 2 -W 1 $SVC_IP; echo '---'; wget -qO- http://$SVC_IP/hostname"
```

예상 출력:
```
2 packets transmitted, 0 packets received, 100% packet loss   ← ping 실패!
---
echo-5d8f7c6b9-bbbbb                                          ← HTTP는 성공!
```

✅ **이 모듈의 하이라이트**: ping(ICMP)은 안 되는데 HTTP(TCP 80)는 됩니다. iptables 규칙이 **TCP 80 포트에 대해서만** DNAT을 걸어놨기 때문. ClusterIP는 핑 쏠 "장비"가 아니라 규칙 속 번호일 뿐입니다. — "Service가 죽었나 ping 해봐야지"가 왜 무의미한지 체득.

## Step 4. 고장 재현 ① — selector 오타

```bash
kubectl patch svc echo -p '{"spec":{"selector":{"app":"echo"}}}'   # echo → echo 오타
kubectl get endpointslices
```

예상 출력:
```
echo-xxxxx   IPv4   <unset>      ← ENDPOINTS가 비었습니다!
```

```bash
kubectl run client --rm -it --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  wget -qO- -T 3 http://echo/hostname
# → wget: download timed out
```

✅ **"연결 안 됨" 디버깅 공식 1번: EndpointSlice가 비었으면 selector vs Pod 라벨 불일치.** 복구:

```bash
kubectl patch svc echo -p '{"spec":{"selector":{"app":"echo"}}}'
```

## Step 5. 고장 재현 ② — targetPort 불일치

```bash
kubectl patch svc echo --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":9999}]'
kubectl run client --rm -it --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  wget -qO- -T 3 http://echo/hostname
```

예상: `Connection refused` 또는 타임아웃. **명단(EndpointSlice)에는 IP가 있는데 포트가 틀린 경우.** 복구:

```bash
kubectl patch svc echo --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":8080}]'
```

## Step 6. 고장 재현 ③ — Pod가 Ready가 아님

```bash
# readiness probe를 일부러 실패시킴 (agnhost의 /healthz를 막을 순 없으니 존재하지 않는 경로로 변경)
kubectl patch deploy echo --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/nope"}]'
kubectl rollout status deploy/echo --timeout=30s; kubectl get pods -l app=echo
```

예상 출력:
```
echo-...   0/1   Running   ← 살아는 있는데 READY 0/1
```

```bash
kubectl get endpointslices
# → ENDPOINTS에서 새 Pod들이 빠져 있음 (또는 conditions: ready=false)
```

✅ **Running ≠ Ready ≠ 트래픽 수신.** 명단에 오르는 조건은 Ready입니다. 복구:

```bash
kubectl patch deploy echo --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/healthz"}]'
```

## 디버깅 공식 정리 (외울 것)

```
Service 연결 안 됨?
1. kubectl get endpointslices  → 비었나요?
   비었으면 → selector vs Pod 라벨 비교 / Pod가 Ready인지 확인
2. 안 비었으면 → targetPort vs 컨테이너 실제 포트 비교
3. 그래도면 → NetworkPolicy(모듈 15), DNS(모듈 16) 의심
```

## 정리

다음 lab에서 echo를 계속 씁니다. 그대로 두기.
