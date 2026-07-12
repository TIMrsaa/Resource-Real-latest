# Lab 02 — ns 간 정책과 egress(+DNS 함정)

## Step 1. 모니터링 ns에서 shop으로 — namespaceSelector

시나리오: monitoring ns의 수집기가 shop의 모든 Pod 메트릭을 긁어야 합니다.

```bash
kubectl create ns monitoring
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: scraper
  namespace: monitoring
  labels: { run: scraper }
spec:
  containers:
    - name: scraper
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/scraper -n monitoring

# 현재는 차단 (lab-01의 기본 거부)
kubectl exec -n monitoring scraper -- wget -qO- -T 3 http://api.shop/hostname || echo BLOCKED
```

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-monitoring, namespace: shop }
spec:
  podSelector: {}                # shop의 모든 Pod에
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring   # ns 이름 라벨 (자동 부여)
    ports: [{ protocol: TCP, port: 8080 }]
EOF
sleep 5
kubectl exec -n monitoring scraper -- wget -qO- -T 3 http://api.shop/hostname
```

예상: `api` 응답 — **허용은 합집합**이므로 기존 정책들과 충돌 없이 더해졌습니다.

## Step 2. egress 통제 — 그리고 DNS 함정에 일부러 빠지기

시나리오: db Pod는 어디로도 나가면 안 됩니다(데이터 유출 차단). 단 frontend는 api로만.

```bash
# 일부러 DNS 허용 없이 frontend egress를 잠급니다
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: frontend-egress, namespace: shop }
spec:
  podSelector: { matchLabels: { app: frontend } }
  policyTypes: [Egress]
  egress:
  - to: [{ podSelector: { matchLabels: { app: api } } }]
    ports: [{ protocol: TCP, port: 8080 }]
EOF
sleep 5
kubectl exec -n shop frontend -- wget -qO- -T 3 http://api/hostname || echo "FAILED?!"
```

예상 출력:
```
FAILED?!        ← 허용했는데 실패!
```

원인 추적 — IP로 직접 호출하면?

```bash
API_IP=$(kubectl get pod api -n shop -o jsonpath='{.status.podIP}')
kubectl exec -n shop frontend -- wget -qO- -T 3 http://$API_IP:8080/hostname
```

예상: 성공! ✅ **이름만 안 되는 것 = DNS가 막힌 것.** egress 통제가 kube-dns(53)로의 질의까지 막았습니다. 수리:

```bash
kubectl patch networkpolicy frontend-egress -n shop --type=json -p='[{"op":"add","path":"/spec/egress/-","value":{"to":[{"namespaceSelector":{},"podSelector":{"matchLabels":{"k8s-app":"kube-dns"}}}],"ports":[{"protocol":"UDP","port":53},{"protocol":"TCP","port":53}]}}]'
sleep 5
kubectl exec -n shop frontend -- wget -qO- -T 3 http://api/hostname    # → api 
```

✅ **egress 정책 = 본 규칙 + DNS 조각** 세트라는 것을 몸으로 익혔습니다.

## Step 3. db 완전 봉쇄 (egress 전부 거부)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: db-no-egress, namespace: shop }
spec:
  podSelector: { matchLabels: { app: db } }
  policyTypes: [Egress]
  # egress 섹션 자체가 없음 = 아무것도 허용 안 함
EOF
sleep 5
kubectl exec -n shop db -- wget -qO- -T 3 http://api/hostname || echo "EGRESS BLOCKED"
kubectl exec -n shop db -- sh -c 'wget -qO- -T 3 http://1.1.1.1 2>&1 | head -1' || echo "INTERNET BLOCKED"
```

예상: 둘 다 BLOCKED — DB가 탈취당해도 데이터를 밖으로 보낼 수 없습니다. (단, **응답**은 가능: api→db 요청의 응답은 stateful 추적으로 허용 — db는 여전히 제 역할을 합니다)

```bash
kubectl exec -n shop api -- wget -qO- -T 3 http://db/hostname    # → db (정상 서비스 확인)
```

## Step 4. 정책 현황 감사

```bash
kubectl get networkpolicy -n shop
kubectl describe networkpolicy frontend-egress -n shop
```

> 💡 시각화 도구: 정책이 수십 장 되면 https://editor.networkpolicy.io (Cilium 제공) 같은 시각 편집기가 유용합니다.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| 정책 만들어도 다 뚫림 | 집행자 미활성 (lab-01 Step 0) / 정책 지원 없는 CNI |
| 허용했는데 timeout | 포트가 Service 포트(80)로 적혀 있지 않은지 — 컨테이너 포트(8080)로 |
| 이름으론 안 되고 IP론 됨 | DNS egress 누락 (Step 2) |
| 응답이 안 와요 | 방향 혼동 — ingress 허용이면 응답은 자동. **새 연결**의 방향만 따져라 |

## 정리

```bash
bash cleanup.sh
```
