# 자가 점검 퀴즈

**Q1.** Pod의 /etc/resolv.conf는 누가 만들고, nameserver IP의 정체는?

**Q2.** `api`라는 한 단어가 `api.default.svc.cluster.local`로 풀리는 메커니즘은?

**Q3.** ndots:5 환경에서 `s3.ap-northeast-2.amazonaws.com`(점 4개) 1회 해석에 발생하는 질의 횟수는? (search 4개 가정)

**Q4.** ndots 문제의 해결책 3가지와 각각의 트레이드오프는?

**Q5.** 일반 Service와 Headless Service의 DNS 응답 차이와, Headless의 대표 용처는?

**Q6.** "②CoreDNS Pod에 직접 질의하면 되는데 kube-dns Service로는 안 된다" — 무엇이 고장났나요?

**Q7.** EKS에서 Corefile을 커스텀하는 올바른 방법과 잘못된 방법은?

---

## 정답

**A1.** **kubelet**이 dnsPolicy(기본 ClusterFirst)에 따라 생성. nameserver는 **kube-dns Service의 ClusterIP** (구현체는 CoreDNS Pod들).

**A2.** 점 개수(0) < ndots(5)이므로 search 목록의 첫 항목 `default.svc.cluster.local`을 붙여 질의 → 매칭 성공.

**A3.** 점 4 < 5 → search 4개를 먼저 시도(전부 NXDOMAIN) 후 절대 이름 — **5회**.

**A4.** ① FQDN(끝에 점): 가장 확실하지만 코드/설정 수정 필요 ② dnsConfig로 ndots 하향(예: 2): 손쉽지만 중간 형태 이름(`db.shop`)의 해석 순서가 바뀜 ③ NodeLocal DNSCache: 질의 자체는 줄지 않으나 노드 캐시가 흡수, 클러스터 차원 해결 (설치/운영 비용).

**A5.** 일반: ClusterIP **1개** 반환(분배는 kube-proxy). Headless(clusterIP: None): **모든 Ready Pod의 IP**를 반환 — 클라이언트가 직접 선택. 용처: StatefulSet 멤버 직통(db-0 지명), 클라이언트 사이드 LB.

**A6.** CoreDNS는 정상, **Service 경로**가 고장 — kube-proxy 규칙, kube-dns Service/EndpointSlice를 의심. (이분 탐색: 직접=OK, 경유=실패 → 경유 구간이 범인)

**A7.** 올바름: 관리형 애드온의 **configuration values**로 corefile 설정. 잘못: ConfigMap 직접 수정 — 동작은 하지만 애드온 업그레이드 시 덮여 사라집니다.
