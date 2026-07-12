# Lab 01 — DNS 레코드 체계와 resolv.conf 해부

## Step 0. 도구 Pod (nslookup/dig 내장)

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: dnsutil
  labels: { run: dnsutil }
spec:
  containers:
    - name: dnsutil
      image: registry.k8s.io/e2e-test-images/agnhost:2.53
      args: ["sleep", "3600"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
  labels: { app: echo }
spec:
  replicas: 2
  selector:
    matchLabels: { app: echo }
  template:
    metadata:
      labels: { app: echo }
    spec:
      containers:
        - name: agnhost
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          command: ["/agnhost", "netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: echo
spec:
  selector: { app: echo }
  ports:
    - port: 80
      targetPort: 8080
EOF
kubectl wait --for=condition=Ready pod/dnsutil
```

## Step 1. resolv.conf — kubelet의 작품

```bash
kubectl exec dnsutil -- cat /etc/resolv.conf
```

예상 출력:
```
nameserver 172.20.0.10
search default.svc.cluster.local svc.cluster.local cluster.local ap-northeast-2.compute.internal
options ndots:5
```

```bash
# nameserver의 정체 = kube-dns Service
kubectl get svc -n kube-system kube-dns
```

✅ nameserver IP가 kube-dns의 ClusterIP와 일치 — "모든 Pod의 DNS 질의는 이 Service로" 구조 확인.

## Step 2. 이름 확장 실험 — search 목록의 작동

```bash
kubectl exec dnsutil -- nslookup echo                       # 짧은 이름
kubectl exec dnsutil -- nslookup echo.default               # ns 포함
kubectl exec dnsutil -- nslookup echo.default.svc.cluster.local   # FQDN
```

예상: 셋 다 **같은 ClusterIP**. 셋의 차이는 결과가 아니라 **질의 횟수**입니다(lab-02에서 측정).

## Step 3. Headless — 대표번호 없는 명단

```bash
# 같은 Pod들을 가리키는 Headless Service 추가
kubectl create service clusterip echo-headless --clusterip=None --tcp=80:8080 2>/dev/null || \
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata: { name: echo-headless }
spec:
  clusterIP: None
  selector: { app: echo }
  ports: [{ port: 80, targetPort: 8080 }]
EOF
# selector 보정 (create service는 selector를 이름 기준으로 잡으므로)
kubectl patch svc echo-headless -p '{"spec":{"selector":{"app":"echo"}}}'

kubectl exec dnsutil -- nslookup echo            # 일반: IP 1개 (ClusterIP)
kubectl exec dnsutil -- nslookup echo-headless   # Headless: IP 여러 개!
```

예상 출력:
```
Name: echo...                Name: echo-headless...
Address: 172.20.x.x          Address: 192.168.a.a     ← Pod IP들이 직접!
                             Address: 192.168.b.b
```

✅ 같은 백엔드인데 일반 Service는 가상 IP 1개, Headless는 **Pod 명단**을 반환. StatefulSet(모듈 19)의 멤버 직통 연결이 이 메커니즘 위에 섭니다.

## Step 4. 역방향/SRV (참고)

```bash
CLUSTER_IP=$(kubectl get svc echo -o jsonpath='{.spec.clusterIP}')
kubectl exec dnsutil -- nslookup $CLUSTER_IP                          # PTR: IP → 이름
kubectl exec dnsutil -- nslookup -type=SRV _80-8080._tcp.echo.default.svc.cluster.local 2>/dev/null \
  || kubectl exec dnsutil -- nslookup -q=srv echo.default.svc.cluster.local
```

## Step 5. DNS 장애 디버깅 루틴 (저장해둘 것)

```bash
# ① CoreDNS 살아있나
kubectl get pods -n kube-system -l k8s-app=kube-dns
# ② 직접 질의는 되나 (Service를 우회해 Pod에 바로)
COREDNS_POD_IP=$(kubectl get pod -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].status.podIP}')
kubectl exec dnsutil -- nslookup echo $COREDNS_POD_IP
# ③ CoreDNS 에러 로그
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
# ④ CoreDNS 메트릭 (질의량/캐시 적중)
kubectl exec dnsutil -- wget -qO- http://$COREDNS_POD_IP:9153/metrics 2>/dev/null | grep -E "^coredns_dns_requests_total|^coredns_cache_hits" | head -5
```

루틴의 의미: ②가 되는데 일반 질의가 안 되면 **kube-dns Service/kube-proxy** 문제, ②부터 안 되면 **CoreDNS 자체** 문제 — 절반씩 잘라 들어가는 이분 탐색.

## 정리

다음 lab에서 dnsutil/echo 계속 사용.
