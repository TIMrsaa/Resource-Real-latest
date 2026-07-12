# Lab 02 — ndots 문제 재현과 Corefile 커스텀

## Step 1. CoreDNS에 질의 로그 켜기 (관찰 도구)

EKS 관리형 애드온의 정석 경로 대신, 학습용으로 ConfigMap을 직접 잠깐 수정합니다:

```bash
kubectl -n kube-system get configmap coredns -o yaml > /tmp/coredns-backup.yaml
# Corefile에 log 플러그인 삽입 (errors 다음 줄에)
kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' \
  | sed 's/errors/errors\n    log/' > /tmp/Corefile
kubectl -n kube-system create configmap coredns --from-file=Corefile=/tmp/Corefile \
  -o yaml --dry-run=client | kubectl apply -f -
# reload 플러그인이 ~30초 내 자동 반영
sleep 35
```

## Step 2. ndots 증폭 재현 — 외부 도메인 1번 호출에 질의 5번

터미널 1 (CoreDNS 로그 감시):
```bash
kubectl logs -n kube-system -l k8s-app=kube-dns -f | grep -v healthz
```

터미널 2:
```bash
kubectl exec dnsutil -- nslookup www.amazon.com >/dev/null
```

터미널 1 예상 출력 (연속 5줄!):
```
... "A IN www.amazon.com.default.svc.cluster.local." NXDOMAIN ...
... "A IN www.amazon.com.svc.cluster.local." NXDOMAIN ...
... "A IN www.amazon.com.cluster.local." NXDOMAIN ...
... "A IN www.amazon.com.ap-northeast-2.compute.internal." NXDOMAIN ...
... "A IN www.amazon.com." NOERROR ...                ← 5번째에야 진짜 질의!
```

✅ **이론의 ndots:5가 패킷으로 보였습니다.** 외부 호출이 많은 서비스라면 CoreDNS 부하의 80%가 이 NXDOMAIN 쓰레기일 수 있습니다.

## Step 3. 해결책 검증

```bash
# 해결 ① FQDN (끝의 점)
kubectl exec dnsutil -- nslookup www.amazon.com. >/dev/null
# → 터미널 1에 질의 1번만!

# 해결 ② Pod dnsConfig로 ndots 하향
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: lowdots }
spec:
  dnsConfig:
    options: [{ name: ndots, value: "2" }]
  containers:
  - { name: c, image: registry.k8s.io/e2e-test-images/agnhost:2.53, command: [sleep, "3600"] }
EOF
kubectl wait --for=condition=Ready pod/lowdots
kubectl exec lowdots -- nslookup www.amazon.com >/dev/null    # 점2 ≥ ndots2 → 절대 이름 먼저
kubectl exec lowdots -- nslookup echo >/dev/null              # 점0 < 2 → search 여전히 동작
```

✅ 터미널 1 확인: lowdots의 외부 질의는 1번, 내부 짧은 이름도 여전히 동작 — 실용적 절충.

## Step 4. Corefile 커스텀 — 사내 도메인 분기 (패턴 학습)

"corp.example.com은 사내 DNS(예: 10.0.0.2)로 보내라" 시나리오:

```bash
cat /tmp/Corefile   # 현재 구조 확인 후, 별도 서버 블록을 추가하는 형태
```

추가할 블록 (참고용 — 실제 사내 DNS가 없으므로 적용은 생략):
```
corp.example.com:53 {
    errors
    cache 30
    forward . 10.0.0.2 10.0.0.3
}
```

> 💡 EKS 정석: ConfigMap 직접 수정은 애드온 업그레이드 때 덮일 수 있습니다. 운영에서는 `aws eks update-addon --addon-name coredns --configuration-values` 의 corefile 설정으로 관리하세요.

## Step 5. 원상 복구

```bash
kubectl apply -f /tmp/coredns-backup.yaml
rm -f /tmp/Corefile /tmp/coredns-backup.yaml
```

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| log가 안 찍힘 | reload 대기(30s) / Corefile 문법 오류 — CoreDNS Pod 로그에 파싱 에러 확인 |
| Corefile 수정 후 클러스터 전체 DNS 다운 | 문법 오류로 CoreDNS crash — 백업으로 즉시 복구 (그래서 Step 1에서 백업부터) |
| 외부 질의가 아예 안 됨 | forward 대상(노드 resolv.conf) 문제 / NetworkPolicy egress(모듈 15) |

## 정리

```bash
bash cleanup.sh
```
