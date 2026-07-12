# 자가 점검 퀴즈

**Q1.** CoreDNS의 플러그인 체인 실행 모델을 설명하세요. `fallthrough`의 역할은? 순서에 관한 흔한 오해는?

**Q2.** `ndots:5`와 search 도메인이 만드는 증폭을 `google.com` 예로 계산하세요. FQDN이 왜 이것을 피하나요?

**Q3.** Headless Service의 DNS 응답은 ClusterIP Service와 어떻게 다른가? 그것이 09의 무엇을 가능하게 하나요?

**Q4.** 5초 지연 장애의 진짜 원인과, CoreDNS 스케일이 소용없는 이유는? 확인 명령은?

**Q5.** NodeLocal DNSCache의 세 가지 효과는?

**Q6.** `Loop detected`로 CoreDNS가 죽을 때의 원인과 올바른 해법은? loop 플러그인을 지우면?

**Q7.** CoreDNS의 건강을 보는 메트릭 3종과, 캐시 히트율이 낮을 때의 원인은?

**Q8.** CoreDNS 운영에서 잊기 쉬운 배치 요건 둘과, 그것이 없을 때의 최악 시나리오는?

---

## 정답

**A1.** 질의가 플러그인 체인을 타고 흐르며, 어떤 플러그인이 응답하면 거기서 종료됩니다. `fallthrough`는 "이 플러그인이 답할 수 없는 경우 다음 플러그인으로 넘기라"는 지시다(예: kubernetes 플러그인이 in-addr.arpa를 못 답하면 forward로). 흔한 오해: Corefile에 적은 나열 순서가 실행 순서라고 생각하는 것 — 실제 실행 순서는 컴파일 시점의 `plugin.cfg`에 정의된 고정 순서를 따릅니다(cache는 항상 forward보다 앞). 순서는 고정, 흐름은 응답 여부가 정합니다.

**A2.** `google.com`은 점이 1개로 ndots(5) 미만이므로 search 도메인을 먼저 붙입니다: ① google.com.default.svc.cluster.local(NXDOMAIN) ② google.com.svc.cluster.local(NXDOMAIN) ③ google.com.cluster.local(NXDOMAIN) ④ google.com(성공) — 4번, A와 AAAA를 모두 물으면 8번. FQDN(`google.com.` 끝에 점)은 이미 완전한 이름임을 뜻하므로 리졸버가 search 순회를 건너뜁니다.

**A3.** ClusterIP Service는 하나의 A 레코드(ClusterIP)를 반환하고, Headless(clusterIP: None)는 **모든 Pod IP를 A 레코드 여러 개로** 반환합니다. 또 `<hostname>.<svc>.<ns>.svc.cluster.local`로 개별 Pod를 직접 지목할 수 있습니다. 이것이 09의 StatefulSet이 제공하는 **안정적 네트워크 ID**의 기반이고, gRPC 같은 클라이언트 사이드 로드밸런싱과 분산 시스템의 멤버 발견(peer discovery)을 가능하게 합니다.

**A4.** 원인은 리눅스 커널의 conntrack DNAT 경쟁 조건 — 같은 소켓에서 A·AAAA 질의를 동시에 보내면 두 UDP 패킷의 conntrack 항목 삽입이 경쟁하고 하나가 드롭되며, glibc가 5초 타임아웃 후 재시도합니다. CoreDNS는 애초에 그 질의를 받지도 못했으므로(패킷이 커널에서 드롭) 스케일해도 무의미합니다. 확인: `conntrack -S | grep insert_failed`가 증가하는지, 그리고 CoreDNS의 p99 지연이 정상(수 ms)인지 대조.

**A5.** ① 지연: 캐시 히트가 노드 로컬(169.254.20.10)에서 종료 — 네트워크 홉 0. ② 5초 문제 해소: 링크로컬 인터페이스라 conntrack DNAT가 개입하지 않습니다. ③ 부하 감소: CoreDNS로 가는 QPS가 히트율만큼 줄고, 업스트림 연결을 TCP로 유지·재사용합니다. 이 셋 때문에 "가장 효과적인 단일 처방"으로 꼽힙니다.

**A6.** 노드의 `/etc/resolv.conf`가 systemd-resolved의 stub(127.0.0.53)을 가리키는데 CoreDNS의 `forward . /etc/resolv.conf`가 그것을 상위 DNS로 삼아, 질의가 자기 자신에게 돌아오며 무한 순환합니다 — loop 플러그인이 이를 감지해 프로세스를 종료시킵니다. 해법: kubelet의 `--resolv-conf=/run/systemd/resolve/resolv.conf`(실제 업스트림)로 지정하거나 Corefile의 forward 대상을 명시(8.8.8.8 등). loop 플러그인을 지우면 Pod는 살지만 질의가 무한 순환하며 CPU를 태우다 타임아웃됩니다 — **loop는 병이 아니라 경보기입니다.**

**A7.** `coredns_dns_requests_total`(QPS), `coredns_dns_request_duration_seconds`(지연 분포 — histogram_quantile로 p99), `coredns_cache_hits_total`/`coredns_cache_misses_total`(히트율). 히트율이 낮은 원인: ndots 증폭으로 NXDOMAIN 헛질문이 쏟아지거나(denial 캐시 TTL이 짧음), 레코드 TTL이 짧거나, 고유한 이름이 많아 캐시가 의미 없는 경우. 대응: cache TTL 조정, NodeLocal DNSCache, ndots 조정, autopath.

**A8.** ① PodDisruptionBudget(minAvailable ≥ 1) ② podAntiAffinity(노드 분산). 없으면: 기본 replicas 2가 같은 노드에 스케줄될 수 있고, 클러스터 업그레이드의 노드 드레인에서 두 Pod가 동시에 퇴거됩니다 → **클러스터 전체의 이름 해석이 멈추고** 모든 서비스 호출이 실패합니다. 애플리케이션 로그에는 "connection refused"만 보여 원인 파악이 늦습니다. 클러스터 업그레이드 체크리스트의 첫 항목이어야 합니다.
