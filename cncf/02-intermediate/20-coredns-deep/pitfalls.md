# 흔한 함정 5선

## 1. 5초 지연을 CoreDNS 탓으로 돌리고 스케일

p99에 정확히 5.0초 계단이 보이면 반사적으로 CoreDNS replicas를 늘립니다 — 그리고 아무것도 낫지 않습니다. 원인은 커널의 conntrack DNAT 경쟁 조건입니다: 같은 소켓에서 A와 AAAA 질의를 동시에 보내면 두 UDP 패킷의 conntrack 항목 삽입이 경쟁하고, 하나가 드롭되며, glibc가 5초 타임아웃 후 재시도합니다. CoreDNS는 빠르게 답했고 답을 받은 쪽이 없었을 뿐입니다. 확인: `conntrack -S | grep insert_failed`. 처방: NodeLocal DNSCache(로컬이라 DNAT 없음, 가장 확실), `single-request-reopen`, AAAA 비활성. **층을 틀리면 아무리 스케일해도 안 낫습니다.**

## 2. ndots:5를 방치한 채 외부 API를 많이 호출

외부 도메인 하나를 해석하는 데 질의가 네 번(A+AAAA면 여덟 번) 나갑니다 — 대부분이 NXDOMAIN인 헛질문입니다. 외부 API를 초당 수천 번 호출하는 서비스라면 CoreDNS 부하의 절반 이상이 이 헛질문일 수 있습니다(lab-02 Step 2에서 NXDOMAIN 카운터로 확인). 대응은 앱별로: 외부 호출이 많은 Pod만 `dnsConfig.options: [{name: ndots, value: "2"}]`, 또는 코드에서 FQDN(끝에 점) 사용. 전역으로 ndots를 낮추면 내부 짧은 이름(`web`) 해석이 깨질 수 있으니 선별적으로.

## 3. CoreDNS에 PDB와 안티어피니티가 없음

기본 replicas 2가 같은 노드에 스케줄될 수 있고, 노드 드레인(k8s 35의 업그레이드!)에서 두 Pod가 동시에 퇴거될 수 있습니다 — 그 순간 **클러스터 전체의 이름 해석이 멈춥니다.** 모든 서비스 호출이 실패하고, 그 원인을 아무도 즉시 알아채지 못합니다(애플리케이션 로그에는 "connection refused"만 보입니다). `PodDisruptionBudget(minAvailable: 1)`과 `podAntiAffinity`는 선택이 아니라 필수이며, 클러스터 업그레이드 체크리스트의 첫 항목이어야 합니다.

## 4. loop 플러그인을 지워서 CrashLoop을 "해결"

CoreDNS가 `Loop ... detected`로 죽으면 Corefile에서 `loop`를 지우고 싶어집니다 — 그러면 Pod는 살아나고 DNS 질의는 무한 순환하며 CPU를 태우다 타임아웃됩니다. 진짜 원인은 `forward . /etc/resolv.conf`가 가리키는 노드의 resolv.conf가 systemd-resolved의 stub(127.0.0.53)을 가리켜서 CoreDNS가 자기 자신에게 forward하는 것입니다. 해법은 kubelet의 `--resolv-conf`를 실제 업스트림(`/run/systemd/resolve/resolv.conf`)으로 지정하거나 Corefile에서 forward 대상을 명시하는 것. **loop 플러그인은 병이 아니라 경보기입니다.**

## 5. Corefile의 나열 순서가 실행 순서라고 착각

CoreDNS의 플러그인 실행 순서는 Corefile에 적은 순서가 아니라 **컴파일 시점의 `plugin.cfg`에 정의된 고정 순서**를 따릅니다. 그래서 `cache`를 위에 적든 아래에 적든 실행 순서는 같습니다(cache는 항상 forward보다 앞). 이것을 모르면 "순서를 바꿨는데 동작이 같다"거나 반대로 "순서대로 동작할 것"이라 잘못 기대합니다. 다만 `fallthrough`와 각 플러그인의 응답 여부가 체인의 흐름을 결정한다는 것은 사실입니다 — 순서 자체는 고정, 흐름은 응답 여부가 정한다는 두 사실을 함께 기억하세요.

## 실무 사고 사례

> 한 회사의 SRE가 몇 달째 미스터리를 쫓고 있었습니다: 결제 서비스의 p99 지연이 하루에 몇 번씩 5초대로 튀는데, 애플리케이션 트레이스(13)를 보면 **HTTP 클라이언트 span의 시작 전**에 5초가 사라져 있었습니다. 코드에는 아무것도 없는 구간이었습니다. APM 벤더는 "네트워크 문제"라고 했고, 네트워크 팀은 "우리 쪽은 정상"이라고 했습니다. 전환점은 한 엔지니어가 `strace`로 프로세스를 붙잡고 본 순간이었습니다 — `sendto(A 질의)`, `sendto(AAAA 질의)` 직후 정확히 5.000초의 정적, 그리고 재전송. DNS였습니다. 그러나 CoreDNS의 메트릭은 완벽했습니다(p99 3ms, 에러 0). 답은 커널에 있었습니다: `conntrack -S`의 `insert_failed`가 초당 수십씩 증가하고 있었습니다. 두 UDP 질의가 같은 소켓에서 동시에 나가며 DNAT 항목 삽입이 경쟁했고, 진 쪽 패킷이 조용히 드롭됐으며, glibc의 기본 타임아웃이 5초였던 것입니다. 조직이 취한 조치는 세 겹이었습니다: ① NodeLocal DNSCache 배포 — 링크로컬 주소라 DNAT 자체가 없습니다. 5초 스파이크가 즉시 사라졌습니다. ② 부수 효과가 더 컸습니다: CoreDNS로 가는 QPS가 78% 감소했고(캐시 히트), 그 결과 DNS p99가 3ms에서 0.4ms로. ③ 외부 API 호출이 많은 서비스들에 `ndots: 2`를 적용해 헛질문을 제거. 회고에서 나온 문장이 이 모듈의 요지입니다: "우리는 **DNS를 관측하고 있지 않았습니다** — CoreDNS를 관측하고 있었을 뿐입니다. 문제는 클라이언트와 CoreDNS 사이의 커널에 있었고, 그 구간에는 어떤 대시보드도 없었습니다." 이름 해석은 모든 요청의 첫 홉이고, 그 홉이 조용히 5초를 먹으면 어떤 애플리케이션 최적화도 무의미합니다.
