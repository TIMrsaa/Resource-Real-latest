# 자가 점검 퀴즈

**Q1.** eBPF가 커널 모듈과 달리 안전한 이유 세 가지는? 맵의 역할은?

**Q2.** Cilium의 상태(Service·identity·정책·conntrack)는 어디에 저장되나요? cilium-agent와 커널 프로그램의 역할 분담은?

**Q3.** identity란 무엇이고, 왜 IP 대신 identity로 정책을 집행하나요? 규칙 수는 무엇에 비례하나요?

**Q4.** kube-proxy 대체가 iptables 대비 갖는 이점 두 가지는? socket-level LB가 20의 무엇을 완화하나요?

**Q5.** L3/L4 정책과 L7 정책의 데이터 경로 차이와, 그로부터 나오는 운영 원칙은?

**Q6.** toFQDNs 정책은 어떻게 동작하나요? 20의 무엇과 결합되나요?

**Q7.** Hubble이 전통적 네트워크 모니터링과 구조적으로 다른 점은? eks 18의 무엇에 답하나요?

**Q8.** Cilium 도입의 정직한 대가 다섯 가지를 들어라.

---

## 정답

**A1.** ① 검증기(verifier)가 로드 시점에 정적 분석으로 무한 루프 없음·메모리 안전·종료 보장을 확인해 통과 못 하면 아예 로드되지 않습니다. ② JIT 컴파일로 네이티브 속도를 내되 샌드박스 안에서 실행됩니다. ③ 정해진 훅 지점과 헬퍼 함수만 사용 가능해 임의의 커널 메모리를 건드릴 수 없습니다 — 그래서 커널 모듈과 달리 패닉·크래시를 일으키지 않습니다. 맵의 역할: 프로그램은 작고 단순하게 유지하고 상태(IP→identity, Service→백엔드, conntrack 등)는 커널↔유저 공유 맵에 두어, agent가 갱신하고 커널 프로그램은 조회만 합니다.

**A2.** eBPF 맵에 저장됩니다 — cilium_lb4_services/backends(Service), cilium_ipcache(IP→identity), cilium_policy_*(엔드포인트별 정책 결정), cilium_ct4_global(conntrack), cilium_lxc(엔드포인트). 역할 분담: cilium-agent(유저스페이스)가 K8s API를 watch해 이 맵들을 갱신하고, 커널의 eBPF 프로그램은 패킷 처리 시 맵을 조회할 뿐입니다 — 복잡한 제어 로직은 유저스페이스에, 빠른 데이터 경로는 커널에.

**A3.** identity는 Pod의 보안 관련 라벨 집합에 부여된 숫자 ID입니다(같은 라벨 집합의 모든 Pod가 같은 identity, IP·노드와 무관). IP 대신 쓰는 이유: K8s에서 Pod IP는 재생성마다 바뀌지만 identity는 라벨이 같으면 불변이라, IP 변경에도 정책이 그대로 유효합니다(lab-01 Step 5에서 실증). 규칙 수는 Pod 수가 아니라 **라벨 조합 수**에 비례합니다 — 이것이 대규모 클러스터에서의 확장성 근거입니다.

**A4.** ① 성능: Service마다 iptables 규칙 체인을 순회하는 대신 cilium_lb4_services 맵을 O(1)로 조회 — Service 수와 무관한 성능. ② socket-level LB: Pod의 connect() 시점(cgroup connect 훅)에서 목적지를 이미 백엔드 Pod IP로 바꿔 DNAT 홉을 제거합니다. 20의 완화: DNAT가 없으니 conntrack 항목이 줄고, A/AAAA 동시 질의의 DNAT 삽입 경쟁(5초 지연의 진범)이 구조적으로 완화됩니다.

**A5.** L3/L4 정책은 순수 eBPF로 커널에서 identity·포트·프로토콜을 맵 조회해 즉시 판정합니다(빠름). L7 정책(HTTP 메서드·경로)은 트래픽을 노드의 Envoy 프록시로 우회시켜 파싱·판정 후 다시 전달합니다 — 지연·CPU 증가, Envoy가 새 장애 지점. 운영 원칙: **L7 정책은 실제로 HTTP 단위 통제가 필요한 소수 엔드포인트에만** 적용합니다. 전 서비스 L7은 eBPF의 성능 이점을 스스로 버리는 것입니다(사고 사례).

**A6.** toFQDNs는 Pod의 DNS 응답을 DNS 프록시가 가로채(관찰) 도메인의 IP를 학습하고, 그 IP를 identity/정책에 동적으로 허용합니다 — "IP를 미리 모르는 외부 서비스(api.stripe.com 등)"에 대한 egress 정책을 가능하게 합니다. 20(CoreDNS)과 결합됩니다: 이름 해석 경로에 DNS 프록시 한 층이 추가되고, 정책이 DNS 응답의 TTL과 IP 변화를 추적해야 합니다(egress로 kube-dns 접근을 함께 열어줘야 하는 것도 이 때문).

**A7.** 전통적 모니터링은 데이터 경로 밖의 에이전트가 패킷을 복사·샘플링해 추측합니다. Hubble은 판정이 일어나는 그 지점(eBPF 프로그램)에서 플로우를 기록하며, **판정 근거(어느 정책이 POLICY_DENIED로 떨궜는지)까지** 함께 남깁니다 — 관찰 지점 = 집행 지점이라 추측이 아니라 사실입니다. eks 18의 VPC Flow Logs가 "패킷이 오갔다"는 알려도 "왜 막혔나"에 답 못 하던 것에 답합니다.

**A8.** ① 커널 버전 요구(기능별로 다른 최소 커널 — 관리형 노드 이미지 확인 필수). ② 디버깅 난이도(iptables -L 대신 cilium-dbg·hubble 학습). ③ 통합 리스크(CNI+LB+정책+관찰이 한 컴포넌트 → 폭발 반경). ④ 기존 iptables 기반 도구·보안 에이전트와의 상호작용·충돌 가능성. ⑤ L7 정책의 Envoy 경유 비용. (+ 데이터 경로 업그레이드 = 노드 롤링과 맵 마이그레이션 검증.) 도입 근거는 "eBPF니까"가 아니라 증상(Service 수천 개, 정책·관찰 통합 요구)이어야 합니다.
