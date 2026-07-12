# 이론 — CoreDNS, 레코드 체계, ndots

> **🌱 17세 눈높이 비유: 학교 전화 교환실**
> 학생(Pod)이 "교무실이요"라고만 말해도 교환원(CoreDNS)이 "아, 너 2학년이니까 2학년 교무실(같은 ns)이구나"라고 알아서 연결해줍니다 — 이게 **search 목록**.
> 부작용: 학생이 "서울시청이요"(외부 도메인)라고 해도 교환원은 일단 "2학년 서울시청... 없네. 본관 서울시청... 없네..." 하고 **교내를 다 뒤진 후에야** 외부로 겁니다 — 이게 **ndots 문제**.

---

## 1. 구성 요소

```
Pod ──(resolv.conf의 nameserver)──▶ kube-dns Service (ClusterIP, 예: 172.20.0.10)
                                       └─▶ CoreDNS Pod × 2 (kube-system, Deployment)
                                             ├─ K8s API watch → Service/Pod 레코드 생성
                                             └─ 그 외 도메인 → 상위(VPC DNS)로 forward
```

- Service 이름은 역사적 이유로 `kube-dns`지만 구현체는 CoreDNS입니다
- Pod의 resolv.conf는 **kubelet이 생성** (dnsPolicy 기준, 기본 ClusterFirst)

## 2. 레코드 체계

| 대상 | 레코드 | 예 |
|------|--------|----|
| Service (일반) | `<svc>.<ns>.svc.cluster.local` → **ClusterIP** | `api.shop.svc.cluster.local` |
| Service (Headless) | 같은 이름 → **모든 Pod IP** (A 레코드 여러 개) | StatefulSet에서 활용 (모듈 19) |
| Pod (StatefulSet 멤버) | `<pod>.<svc>.<ns>.svc.cluster.local` | `db-0.db.shop...` — 개별 지명 |
| SRV | `_<port>._<proto>.<svc>...` → 포트 번호까지 | gRPC 클라이언트 등 |

> **💡 Headless의 의미**: ClusterIP라는 "대표번호"를 안 만들고 DNS가 **구성원 직통번호**를 전부 알려줍니다. 클라이언트가 직접 분배/선택하는 구조(DB 클러스터, 커스텀 LB)에 씁니다.

## 3. resolv.conf 해부 (kubelet이 써준 것)

```
nameserver 172.20.0.10                                   # kube-dns ClusterIP
search default.svc.cluster.local svc.cluster.local cluster.local ap-northeast-2.compute.internal
options ndots:5
```

### 해석 알고리즘

```
질의 이름의 점(.) 개수 ≥ ndots(5)  → 그대로(절대 이름) 먼저 질의
점 개수 < 5                        → search 목록을 순서대로 붙여 질의, 다 실패하면 원래 이름
```

### ndots:5의 비용 계산

`api`(점 0) → `api.default.svc...` 1번에 성공. 짧은 이름의 편리함 ✅
`db.shop`(점 1) → `db.shop.default.svc...`(실패) → `db.shop.svc...`(성공) — 2번
`api.mycompany.com`(점 2) → 내부 4개 다 실패 후 진짜 질의 — **5번 질의 (그중 4번은 쓰레기)** ❌

대규모 트래픽에서 이 4배 증폭이 CoreDNS를 압사시킵니다. 해결책 3종:

| 해결책 | 방법 | 트레이드오프 |
|--------|------|--------------|
| FQDN 사용 | 끝에 점: `api.mycompany.com.` | 코드/설정 수정 필요, 가장 확실 |
| ndots 낮추기 | Pod `dnsConfig: {options: [{name: ndots, value: "2"}]}` | 짧은 내부 이름(`api`)은 여전히 됨(점0<2), `db.shop` 형태가 절대 이름 취급될 수 있어 주의 |
| NodeLocal DNSCache | 노드마다 캐시 DNS | 쓰레기 질의도 캐시가 흡수 (모듈 37) |

## 4. Corefile — CoreDNS 설정

```
.:53 {
    errors
    health { lameduck 5s }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {   # K8s 레코드 플러그인
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
    }
    prometheus :9153          # 메트릭 (관측 스택과 연결)
    forward . /etc/resolv.conf # 나머지는 노드의 DNS(VPC DNS)로
    cache 30                   # 30초 캐시
    loop
    reload                     # ConfigMap 변경 자동 반영
    loadbalance
}
```

- 플러그인 체인 구조 — 위에서 아래로 통과
- `kube-system`의 ConfigMap `coredns`로 관리. **EKS 관리형 애드온이라 직접 수정분은 업그레이드 시 덮일 수 있습니다** — 애드온 configuration values로 관리하는 것이 정석
- 흔한 커스텀: 특정 사내 도메인을 사내 DNS로 `forward corp.example.com 10.0.0.2`, 디버깅용 `log` 플러그인

## 5. dnsPolicy 4종

| 값 | 의미 |
|----|------|
| ClusterFirst (기본) | 위 resolv.conf — 클러스터 DNS 우선 |
| Default | **노드의** resolv.conf 상속 (클러스터 이름 해석 불가) |
| ClusterFirstWithHostNet | hostNetwork Pod인데 클러스터 DNS 쓰고 싶을 때 |
| None | dnsConfig로 완전 수동 |

## 6. 소스코드에서 확인하기

- CoreDNS kubernetes 플러그인: https://github.com/coredns/coredns/tree/master/plugin/kubernetes — Service watch → 레코드 변환
- kubelet의 resolv.conf 생성: `pkg/kubelet/network/dns/dns.go` — search 목록과 ndots:5가 하드코딩처럼 박혀 있는 곳

## 요약 카드

| 질문 | 답 |
|------|----|
| `api`만으로 풀리는 이유? | resolv.conf의 search 목록 (kubelet 작성) |
| ndots:5의 부작용? | 외부 도메인마다 내부 질의 4번 낭비 |
| 가장 깔끔한 해결? | FQDN(끝에 점) 또는 dnsConfig로 ndots 하향 |
| Headless 레코드? | ClusterIP 없이 Pod IP들을 직접 반환 |
| Corefile 위치? | kube-system ConfigMap `coredns` (EKS는 애드온 값으로) |
