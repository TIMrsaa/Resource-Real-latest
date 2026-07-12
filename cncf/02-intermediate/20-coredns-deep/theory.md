# 이론 — 플러그인 체인, K8s 이름 해석, ndots 증폭, 성능, 3대 장애

> **🌱 17세 눈높이 비유: 학교 안내 데스크**
> - **CoreDNS** = 안내 데스크 — "3학년 2반 교실 어디예요?"에 위치를 알려줍니다
> - **플러그인 체인** = 데스크 뒤에 앉은 직원들이 **줄지어** 있습니다. 첫 직원이 답할 수 있으면 거기서 끝, 못 하면 다음 직원에게 넘깁니다
>   - `kubernetes` 직원 = 교내 지도 담당 (Service·Pod 이름)
>   - `forward` 직원 = 교외 문의 담당 (외부 도메인을 상위 기관에 전화)
>   - `cache` 직원 = 최근 답변을 적어둔 메모지
> - **ndots:5** = "이름에 점이 5개 미만이면 교내 이름일 것"이라는 학교 규칙 —
>   그래서 "google.com"(점 1개)도 일단 "google.com.default.svc.cluster.local"부터 물어봅니다 → **헛질문 여러 번**
> - **NodeLocal DNSCache** = 각 층마다 작은 안내판을 설치 — 데스크까지 안 가도 되는 질문은 거기서 해결
> - **5초 지연** = 안내 데스크가 아니라 **복도의 회전문**(커널 conntrack)이 가끔 사람을 가두는 문제

---

## 1. 플러그인 체인 — Corefile은 프로그램입니다

```
.:53 {
    errors                     # 에러 로깅
    health { lameduck 5s }     # /health 엔드포인트
    ready                      # /ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure          # Pod A 레코드 정책
        fallthrough in-addr.arpa ip6.arpa   # ★ 못 답하면 다음 플러그인으로
        ttl 30
    }
    prometheus :9153           # 메트릭
    forward . /etc/resolv.conf { max_concurrent 1000 }   # 상위 DNS
    cache 30                   # 응답 캐시 (성공 30s, 실패는 denial 캐시)
    loop                       # 루프 감지 (자기 자신에게 forward하면 죽습니다)
    reload                     # Corefile 변경 자동 반영
    loadbalance                # A 레코드 순서 셔플
}
```

**실행 모델**: 질의가 위에서 아래로 흐릅니다. 플러그인이 답하면 거기서 종료(체인 중단), `fallthrough`가 있으면 다음으로 넘깁니다. 순서가 곧 로직입니다.

```
순서의 함의:
  cache가 kubernetes '뒤'에 있으면 → 클러스터 레코드와 외부 응답 모두 캐시
  cache가 forward '앞'에 있으면    → 캐시 히트 시 forward 스킵 (일반적 배치)
  ★ 실제 CoreDNS의 플러그인 실행 순서는 plugin.cfg에 정의된 고정 순서를 따릅니다
    (Corefile의 나열 순서가 아니라!) — 이것이 자주 혼동됩니다
```

## 2. K8s 이름 해석 — 레코드의 종류

| 대상 | 이름 | 반환 |
|---|---|---|
| Service (ClusterIP) | `<svc>.<ns>.svc.cluster.local` | ClusterIP (A) |
| **Headless** Service | 같은 이름 | **모든 Pod IP** (A 여러 개) |
| Headless의 개별 Pod | `<hostname>.<svc>.<ns>.svc.cluster.local` | 그 Pod IP |
| 명명된 포트 | `_<port>._<proto>.<svc>.<ns>.svc.cluster.local` | SRV |
| ExternalName | `<svc>.<ns>.svc.cluster.local` | CNAME → 외부 도메인 |
| Pod (pods insecure) | `<ip-dashed>.<ns>.pod.cluster.local` | 그 IP |

```
Headless의 의미(09의 StatefulSet과 연결):
  ClusterIP 없음 → DNS가 모든 Pod IP를 반환 → 클라이언트가 직접 선택
  StatefulSet의 안정적 네트워크 ID(pod-0.svc...)가 이것으로 성립
```

## 3. ndots:5 — 쿼리 증폭의 진원지

```
/etc/resolv.conf (Pod 기본):
  nameserver 10.96.0.10
  search default.svc.cluster.local svc.cluster.local cluster.local
  options ndots:5

규칙: 질의하는 이름의 점(.) 개수가 ndots 미만이면 → search 도메인을 먼저 붙여 시도
```

```
"payment" (점 0개 < 5) 를 해석하면:
  ① payment.default.svc.cluster.local   ← 대개 여기서 성공
"google.com" (점 1개 < 5) 를 해석하면:
  ① google.com.default.svc.cluster.local   NXDOMAIN
  ② google.com.svc.cluster.local           NXDOMAIN
  ③ google.com.cluster.local               NXDOMAIN
  ④ google.com                             ✅ 성공
  → 4번의 질의(각각 A+AAAA면 8번!)  ★ 외부 도메인 호출이 많으면 재앙

"google.com." (끝에 점 = FQDN) 은 search를 건너뜁니다 → 1번(또는 2번)
```

대응:

```yaml
# ① Pod의 dnsConfig로 ndots 낮추기 (외부 호출이 많은 앱)
spec:
  dnsConfig:
    options: [{ name: ndots, value: "2" }]

# ② 코드에서 FQDN 사용 (끝에 점) — "google.com."
# ③ autopath 플러그인 — CoreDNS가 search 순회를 대신 해서 1회 왕복으로 (부하는 CoreDNS로)
# ④ NodeLocal DNSCache — 헛질문도 노드 로컬에서 캐시 (§4)
```

## 4. 성능 — 캐시와 NodeLocal DNSCache

```
CoreDNS 캐시(cache 30):
  성공 응답 30초, NXDOMAIN도 denial 캐시(기본 5초) — ndots 헛질문 완화

NodeLocal DNSCache (k8s 애드온):
  각 노드에 DNS 캐시 DaemonSet(169.254.20.10) → Pod의 resolv.conf가 이것을 가리킴
  ✅ 캐시 히트는 노드 로컬에서 종료 (CoreDNS까지 안 감)
  ✅ conntrack UDP 항목이 줄어 §5의 5초 지연 완화
  ✅ 업스트림 연결을 TCP로 유지(연결 재사용)

용량 산정:
  QPS = 앱 요청률 × 요청당 DNS 질의 수(ndots 증폭!) × (1 - 캐시 히트율)
  CoreDNS replicas는 QPS와 CPU로 (기본 2 — 대규모에서는 부족)
  cluster-proportional-autoscaler로 노드 수에 비례 스케일
```

## 5. 3대 장애 — 층이 다릅니다

### ① 간헐적 5초 지연 (커널 층 — CoreDNS 잘못이 아닙니다)

```
원인: 리눅스 커널의 conntrack DNAT 경쟁 조건
  같은 소켓에서 A와 AAAA 질의를 동시에 보내면, 두 UDP 패킷의 DNAT 삽입이 경쟁
  → 하나가 드롭됨 → 클라이언트(glibc)가 5초 타임아웃 후 재시도
증상: p99 지연에 정확히 5.0초 계단
대응:
  - single-request-reopen (dnsConfig options) — 두 질의를 다른 소켓으로
  - AAAA를 아예 끄기 (IPv6 미사용 시)
  - NodeLocal DNSCache (로컬이라 DNAT 없음) ← 가장 확실
  - 커널·CNI 업데이트 (많이 개선됨)
```

### ② 외부 도메인 해석 실패

```
원인: forward 대상이 잘못됨 / loop 감지로 CoreDNS 자기 종료
  - 노드의 /etc/resolv.conf가 127.0.0.53(systemd-resolved)를 가리키면
    CoreDNS가 자기 자신에게 forward → loop 플러그인이 감지해 crash
  - kubelet의 --resolv-conf 를 /run/systemd/resolve/resolv.conf 로
진단: kubectl -n kube-system logs -l k8s-app=kube-dns | grep -i loop
```

### ③ CoreDNS 지연·OOM

```
원인: 쿼리 증폭(ndots) + 낮은 캐시 히트율 + replicas 부족
진단 메트릭:
  coredns_dns_requests_total (QPS)
  coredns_dns_request_duration_seconds (지연 분포)
  coredns_cache_hits_total / coredns_cache_misses_total (히트율!)
  coredns_forward_healthcheck_broken_total (상위 DNS 문제)
대응: replicas↑, cache TTL↑, NodeLocal DNSCache, ndots 조정, autopath
```

## 6. 운영 체크리스트

```
- CoreDNS replicas와 리소스 요청 (기본 2는 소규모용)
- NodeLocal DNSCache 도입 (지연·5초 문제·conntrack 부하 동시 해결)
- 외부 호출이 많은 앱: ndots 조정 또는 FQDN
- 메트릭: QPS, p99 지연, 캐시 히트율, forward 실패
- PodDisruptionBudget (업그레이드 중 DNS 전멸 방지!)
- 안티어피니티 (모든 CoreDNS가 한 노드에 있으면 그 노드 장애 = DNS 전멸)
```

## 7. 소스/도구에서 확인하기

- CoreDNS: https://coredns.io/plugins/ (플러그인 카탈로그)
- K8s DNS 스펙: https://github.com/kubernetes/dns/blob/master/docs/specification.md
- NodeLocal DNSCache: https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
- 5초 지연 분석: "racy conntrack DNS" (Weave/Quentin Machu의 고전 분석)

## 요약 카드

| 질문 | 답 |
|------|----|
| Corefile? | 플러그인 체인 — 답하면 종료, fallthrough면 다음. 순서가 로직 |
| ndots:5의 대가? | 외부 도메인 1회 해석에 질의 4번(A+AAAA면 8번) |
| ndots 대응? | dnsConfig로 낮추기 / FQDN(끝점) / autopath / NodeLocal 캐시 |
| Headless의 DNS? | 모든 Pod IP를 A 레코드로 — StatefulSet 안정 ID의 근거 |
| 5초 지연의 진범? | 커널 conntrack DNAT 경쟁 — CoreDNS 잘못이 아닙니다 |
| 가장 효과적 처방? | **NodeLocal DNSCache** (지연·5초·conntrack 동시 완화) |
| OOM·지연 진단? | QPS, p99, **캐시 히트율**, forward 실패 메트릭 |
| 잊기 쉬운 것? | CoreDNS의 PDB와 안티어피니티 (DNS 전멸 방지) |
