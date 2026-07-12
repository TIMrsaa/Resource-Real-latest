# 자가 점검 퀴즈

**Q1.** ClusterIP로 향한 패킷이 지나는 iptables 체인 3계층의 이름과 각각의 역할은?

**Q2.** 백엔드 4개일 때 KUBE-SVC 체인의 확률 값들은?

**Q3.** DNAT된 연결의 응답 패킷이 올바른 src(Service IP)로 돌아가는 메커니즘은?

**Q4.** "p99에 간헐 타임아웃, 로그 무단서" — L4에서 의심할 테이블과 확인 명령은?

**Q5.** iptables → IPVS 전환을 정당화하는 정량 신호 2가지는?

**Q6.** eBPF kube-proxy 대체의 핵심 아이디어(어디서, 무엇을 바꾸나)는?

**Q7.** externalTrafficPolicy: Local의 효과 2가지와 전제 조건은?

**Q8.** 노드 iptables를 수동으로 고치면 안 되는 이유는?

---

## 정답

**A1.** **KUBE-SERVICES**(모든 Service의 목차 — ClusterIP:port 매칭) → **KUBE-SVC-xxx**(해당 Service의 분배기 — 확률 점프) → **KUBE-SEP-xxx**(엔드포인트 — 실제 DNAT 수행).

**A2.** 0.25 → (남은 셋 중) 0.333... → (남은 둘 중) 0.5 → 잔여 — 각각 최종 25%가 되도록 역산된 값.

**A3.** **conntrack** — 첫 패킷에서 양방향 매핑(원래 5튜플 ↔ 변환 후)을 기록하고, 응답을 테이블 역참조로 자동 복원합니다. 응답용 iptables 규칙은 존재하지 않습니다.

**A4.** **conntrack 테이블 포화** — `sysctl net.netfilter.nf_conntrack_max` vs `/proc/sys/net/netfilter/nf_conntrack_count` (또는 node_nf_conntrack_entries 메트릭) 비교. 한도 근처면 새 연결이 무작위 드롭됩니다.

**A5.** ① `sync_proxy_rules_duration_seconds`의 지속 상승 (규칙 재작성 지연) ② nat 테이블 규칙 수가 수만 단위 (Service/엔드포인트 수천 이상). — 체감/유행이 아니라 측정으로.

**A6.** 커널 훅(소켓 connect, tc/XDP)에 eBPF 프로그램을 장착해 — **패킷마다의 체인 평가를 없애고 연결 수립 시점에 한 번** O(1) 맵 조회로 백엔드를 정합니다 (kube-proxy 컴포넌트 자체 제거).

**A7.** 효과: ① 다른 노드로의 2차 홉 제거(지연↓) ② SNAT 생략으로 **클라이언트 실제 IP 보존.** 전제: 트래픽 받는 노드마다 백엔드 Pod 존재(충분한 replica+분산) + LB 헬스체크가 Pod 없는 노드를 제외.

**A8.** kube-proxy의 주기적 재동기화가 수동 변경을 **덮어쓰거나 충돌**합니다 — 변경이 사라지는 미스터리와 예측 불가 상태를 만듭니다. 의도가 있다면 KUBE-* 밖 체인 또는 NetworkPolicy/상위 레이어에서.
