# Lab 01 — iptables 체인 끝까지 추적하기

## Step 0. 추적용 Service (백엔드 3개)

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chain
  labels: { app: chain }
spec:
  replicas: 3
  selector:
    matchLabels: { app: chain }
  template:
    metadata:
      labels: { app: chain }
    spec:
      containers:
        - name: agnhost
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          command: ["/agnhost", "netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: chain
spec:
  selector: { app: chain }
  ports:
    - port: 80
      targetPort: 8080
EOF
kubectl wait --for=condition=Available deploy/chain
SVC_IP=$(kubectl get svc chain -o jsonpath='{.spec.clusterIP}')
echo "service: $SVC_IP"
kubectl get endpointslices -l kubernetes.io/service-name=chain
```

## Step 1. 노드 진입 + 목차(KUBE-SERVICES)에서 시작

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable
```

노드 셸에서:
```sh
chroot /host
iptables -t nat -L KUBE-SERVICES -n | grep <SVC_IP>
```

예상 출력:
```
KUBE-SVC-XXXXXXXXXXXX  tcp  --  0.0.0.0/0   172.20.x.x   /* default/chain cluster IP */ tcp dpt:80
```

✅ 우리 Service의 목차 줄 발견 — 주석에 `default/chain`이 박혀 있어 사람이 읽을 수 있습니다.

## Step 2. 분배기(KUBE-SVC) — 확률의 실물

```sh
iptables -t nat -L KUBE-SVC-XXXXXXXXXXXX -n    # Step 1에서 본 체인명
```

예상 출력:
```
KUBE-SEP-AAAA...  /* default/chain */ statistic mode random probability 0.33333333349
KUBE-SEP-BBBB...  /* default/chain */ statistic mode random probability 0.50000000000
KUBE-SEP-CCCC...  /* default/chain */
```

✅ **theory의 확률 산수가 그대로**: 1/3 → 1/2 → 잔여. "Service의 분배는 주사위"의 물증.

## Step 3. 엔드포인트(KUBE-SEP) — DNAT의 현장

```sh
iptables -t nat -L KUBE-SEP-AAAA... -n
```

예상 출력:
```
DNAT  tcp  --  ...  tcp to:192.168.x.x:8080      ← 목적지 바꿔치기의 그 줄!
```

✅ Pod IP:8080 — EndpointSlice의 내용이 여기 복제되어 있습니다. **EndpointSlice 갱신 → kube-proxy가 이 체인들을 다시 씀**이 모듈 05 그림의 마지막 조각.

## Step 4. 변경의 전파 속도 관찰

다른 터미널에서:
```bash
kubectl scale deployment chain --replicas=2
```

노드 셸에서 (수 초 후):
```sh
iptables -t nat -L KUBE-SVC-XXXXXXXXXXXX -n
```

예상: SEP 항목이 2개로, 확률이 0.5/잔여로 재계산 — **컨트롤러 체인의 종착지가 이 노드 규칙**임을 실시간으로 확인.

## Step 5. (보너스) 규칙 전체 규모 감 잡기

```sh
iptables-save -t nat | wc -l
iptables-save -t nat | grep -c KUBE-SEP
exit; exit
```

Service/엔드포인트가 수백 개인 운영 클러스터에서 이 숫자가 수만이 됩니다 — IPVS/nftables 세대 교체 논의의 출발점이 이 카운트입니다.

## 정리

chain Deployment/Service는 lab-02에서 계속 사용.
