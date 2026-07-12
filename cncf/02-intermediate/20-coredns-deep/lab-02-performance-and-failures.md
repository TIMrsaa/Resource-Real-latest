# Lab 02 — 캐시·NodeLocal, 그리고 3대 장애의 층 분해

메트릭으로 CoreDNS의 건강을 읽고, 유명한 장애들을 재현·진단합니다.

전제: lab-01의 클러스터(kind: dns).

## Step 1. CoreDNS 메트릭 — 건강의 세 지표

```bash
kubectl -n kube-system port-forward svc/kube-dns 9153:9153 >/dev/null 2>&1 &
sleep 3

echo "=== ① QPS ==="
curl -s http://localhost:9153/metrics | grep "^coredns_dns_requests_total" | head -3
echo ""
echo "=== ② 지연 분포 ==="
curl -s http://localhost:9153/metrics | grep "^coredns_dns_request_duration_seconds_bucket" | tail -3
echo ""
echo "=== ③ 캐시 히트율 (가장 중요) ==="
curl -s http://localhost:9153/metrics | grep -E "^coredns_cache_(hits|misses)_total" | head -4
```

```bash
cat <<'EOF'
캐시 히트율 = hits / (hits + misses)
  낮으면(<70%): ndots 증폭으로 NXDOMAIN이 쏟아지거나, TTL이 짧거나, 고유 이름이 많습니다
  → cache TTL 조정, NodeLocal DNSCache, ndots 조정

PromQL (11):
  sum(rate(coredns_dns_requests_total[5m]))                              QPS
  histogram_quantile(0.99, sum by(le)(rate(coredns_dns_request_duration_seconds_bucket[5m])))
  sum(rate(coredns_cache_hits_total[5m])) / (sum(rate(coredns_cache_hits_total[5m])) + sum(rate(coredns_cache_misses_total[5m])))
EOF
kill %1 2>/dev/null || true
```

## Step 2. 부하를 걸어 증폭 관찰

```bash
kubectl run loadgen --image=nicolaka/netshoot --restart=Never -- sh -c '
for i in $(seq 1 200); do
  getent hosts example.com >/dev/null 2>&1
  getent hosts web >/dev/null 2>&1
done; sleep 3600' 
kubectl wait --for=condition=ready pod/loadgen --timeout=60s
sleep 45

kubectl -n kube-system port-forward svc/kube-dns 9153:9153 >/dev/null 2>&1 &
sleep 3
echo "=== 부하 후 요청 수 (외부 도메인이 몇 배?) ==="
curl -s http://localhost:9153/metrics | grep "coredns_dns_requests_total" | grep -v "^#" | head -4
echo ""
echo "=== NXDOMAIN 응답 (헛질문의 증거) ==="
curl -s http://localhost:9153/metrics | grep 'coredns_dns_responses_total.*NXDOMAIN' | head -2
kill %1 2>/dev/null || true
```

예상: NXDOMAIN이 상당수 — `example.com.default.svc.cluster.local` 등의 헛질문. ✅ **ndots 증폭이 CoreDNS 부하의 상당 부분**임을 숫자로.

## Step 3. 장애 ① 5초 지연 — 층 분해

```bash
cat <<'EOF'
증상: p99 지연에 정확히 5.0초 계단. 애플리케이션 로그에는 아무 이상 없음

진단 순서 (theory §5-①):
  1. CoreDNS의 p99 지연을 봅니다 → 정상(수 ms)
     → CoreDNS는 빠르게 답했습니다. 문제는 그 앞입니다
  2. 클라이언트 측에서 재현: 반복 호출 중 5초짜리가 섞이는가
  3. 노드의 conntrack 통계:
       conntrack -S | grep insert_failed     ← 이것이 증가하면 확정
  4. 원인: 같은 소켓에서 A·AAAA 동시 전송 → 두 UDP의 DNAT 삽입 경쟁 → 하나 드롭
     → glibc가 5초 타임아웃 후 재시도

★ CoreDNS의 잘못이 아닙니다 (커널 층). CoreDNS를 스케일해도 안 낫습니다

대응:
  ① dnsConfig options: single-request-reopen  (A/AAAA를 다른 소켓으로)
  ② AAAA 비활성 (IPv6 미사용 시)
  ③ ★ NodeLocal DNSCache — 로컬 캐시라 DNAT 자체가 없습니다 (가장 확실)
  ④ 커널·CNI 최신화
EOF

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: probe-single-request }
spec:
  containers: [{ name: c, image: nicolaka/netshoot, command: ["sleep","3600"] }]
  dnsConfig:
    options:
      - { name: single-request-reopen }     # A/AAAA를 순차·별도 소켓으로
      - { name: ndots, value: "2" }
EOF
kubectl wait --for=condition=ready pod/probe-single-request --timeout=60s
kubectl exec probe-single-request -- cat /etc/resolv.conf | tail -2
```

## Step 4. 장애 ② 외부 도메인 해석 실패 — loop

```bash
cat <<'EOF'
증상: CoreDNS Pod가 CrashLoopBackOff, 로그에 "Loop ... detected"

원인: 노드의 /etc/resolv.conf가 127.0.0.53(systemd-resolved stub)을 가리킵니다
      → CoreDNS의 forward . /etc/resolv.conf 가 자기 자신(또는 stub)을 향합니다
      → 질의가 무한 순환 → loop 플러그인이 감지하고 프로세스를 죽입니다

진단:
  kubectl -n kube-system logs -l k8s-app=kube-dns | grep -i loop
  kubectl -n kube-system describe cm coredns | grep forward

해결:
  kubelet의 --resolv-conf=/run/systemd/resolve/resolv.conf (실제 업스트림)
  또는 Corefile의 forward를 명시적 DNS(8.8.8.8 등)로
  ★ loop 플러그인을 지우는 것은 해결이 아닙니다 — 무한 순환을 그대로 두는 것
EOF

kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20 2>/dev/null | grep -i loop || echo "(정상 — loop 없음)"
kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' | grep forward
```

## Step 5. 장애 ③ 용량 — replicas·PDB·안티어피니티

```bash
echo "=== CoreDNS의 현재 배치 ==="
kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}'; echo " replicas"
kubectl -n kube-system get pod -l k8s-app=kube-dns -o wide | awk '{print $1, $7}'

echo ""
echo "=== PDB가 있는가요? (업그레이드 중 DNS 전멸 방지) ==="
kubectl -n kube-system get pdb 2>/dev/null | grep -i dns || echo "  ⚠️ PDB 없음!"

echo ""
echo "=== 안티어피니티가 있는가요? (한 노드에 몰리면 그 노드 장애 = DNS 전멸) ==="
kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.template.spec.affinity}' | head -c 200; echo

cat <<'EOF'

운영 필수 (theory §6):
  - PodDisruptionBudget: minAvailable: 1 이상 (노드 드레인 중 전멸 방지)
  - podAntiAffinity: 다른 노드에 분산
  - replicas: 노드 수·QPS에 비례 (cluster-proportional-autoscaler)
  - 리소스 요청/제한: DNS는 지연에 민감 — CPU throttle 주의
EOF
```

## Step 6. NodeLocal DNSCache — 가장 효과적인 처방

```bash
cat <<'EOF'
NodeLocal DNSCache의 3중 효과 (theory §4·§5):
  ① 지연: 캐시 히트가 노드 로컬에서 끝납니다 (네트워크 홉 0)
  ② 5초 문제: 로컬 인터페이스(169.254.20.10)라 conntrack DNAT가 없다 ★
  ③ 부하: CoreDNS로 가는 QPS가 히트율만큼 감소, 업스트림 연결은 TCP로 재사용

배포:
  - DaemonSet(node-local-dns)이 각 노드에 링크로컬 IP로 리스닝
  - kubelet의 --cluster-dns를 그 IP로 (또는 Pod dnsPolicy 조정)
  - Corefile 유사한 자체 설정 (클러스터 도메인은 로컬 처리, 나머지는 CoreDNS로)

측정: 도입 전후로 (a) p99 DNS 지연 (b) CoreDNS QPS (c) conntrack insert_failed
EOF
```

## Step 7. 산출물 — DNS 진단 카드

```markdown
# CoreDNS 진단 카드
| 증상 | 층 | 확인 | 처방 |
|------|----|------|------|
| p99에 정확히 5.0초 | **커널** | conntrack -S \| grep insert_failed | NodeLocal DNSCache, single-request-reopen |
| CoreDNS CrashLoop + "Loop detected" | **설정** | logs \| grep loop, forward 대상 | kubelet --resolv-conf 수정 |
| DNS 전반 느림, CoreDNS CPU 높음 | **용량** | QPS, 캐시 히트율, replicas | replicas↑, cache TTL, ndots, NodeLocal |
| 외부 도메인만 느림 | 증폭 | log 플러그인으로 질의 세기 | FQDN, ndots↓, autopath |
| 노드 드레인 중 DNS 전멸 | 배치 | PDB·안티어피니티 유무 | PDB + antiAffinity |
| Headless가 IP 하나만 반환 | 이해 | Service의 clusterIP: None 확인 | — |

# 메트릭 3종
coredns_dns_requests_total / _duration_seconds / cache_hits+misses (히트율!)
```

## 정리

```bash
bash cleanup.sh
```
