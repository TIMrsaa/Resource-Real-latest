# 자가 점검 퀴즈

**Q1.** CNI의 호출 규약(누가, 언제, 어떻게)을 설명하세요.

**Q2.** Pod의 eth0과 노드의 enixxx 인터페이스의 관계, 그리고 그것을 확인하는 명령 단서는?

**Q3.** K8s 네트워크 4대 요구사항 중 "NAT 없이"가 핵심인 이유는?

**Q4.** VPC CNI와 오버레이(VXLAN) 방식의 차이를 패킷 구조 관점에서 설명하세요.

**Q5.** t3.medium의 max pods가 17인 산수와, 그 한계를 푸는 EKS 기능은?

**Q6.** CPU가 남는데 Pod가 Pending이고 메시지가 `Too many pods`입니다. 원인과 대응 2가지는?

**Q7.** Service 경유 Pod 간 통신의 6단계 여정에서 이 모듈(CNI)이 담당하는 단계는?

**Q8.** CNI DEL이 실패하면 생기는 문제는?

---

## 정답

**A1.** **containerd(kubelet의 위임)** 가 **sandbox 생성/삭제 시점**에, `/opt/cni/bin/`의 플러그인 실행 파일을 **환경변수(CNI_COMMAND=ADD/DEL 등) + stdin JSON 설정**으로 호출하고 stdout JSON(IP 등)을 받는 규약.

**A2.** **veth 페어의 양 끝** — 한쪽은 Pod NET ns(eth0), 한쪽은 노드 ns(enixxx). 단서: `ip addr`에서 서로의 인터페이스 인덱스를 가리키는 `@ifNN` 표기.

**A3.** NAT이 끼면 "Pod가 보는 자기 IP ≠ 상대가 보는 IP"가 되어 — 자기 IP를 광고하는 분산 시스템(DB 클러스터, 피어 디스커버리)이 깨지고, 디버깅 시 주소 추적이 불가능해집니다. 평평한(flat) 네트워크가 K8s 모델의 전제.

**A4.** VPC CNI: 패킷의 src/dst가 **처음부터 끝까지 진짜 VPC IP** — 추가 헤더 없음, VPC 라우팅이 그대로 배달. 오버레이: 원본 패킷을 **노드 간 UDP(VXLAN) 패킷 안에 캡슐화** — [외부: 노드→노드 | 내부: Pod→Pod] 이중 구조, 수신 노드가 개봉.

**A5.** ENI 3개 × ENI당 IPv4 6개 = 18, 노드 자신의 primary IP 1개 제외 = **17.** 해법: **prefix delegation** (ENI에 /28 prefix를 통째로 — max pods 110까지).

**A6.** 노드의 **IP/ENI 한도 도달** (VPC CNI). 대응: ① 더 큰 인스턴스 타입/노드 증설 ② prefix delegation 활성화 (+서브넷 여유 확인, 장기적으로 secondary CIDR).

**A7.** ④⑤ — DNAT으로 정해진 **실제 Pod IP로의 배달**: VPC 라우팅(노드 간) + 노드 내 라우트→veth→Pod. (①DNS=16, ③⑥DNAT/conntrack=28)

**A8.** veth/IP가 회수되지 않는 **IP 누수** — 풀이 서서히 말라 "IP 없음" 장애로. ipamd가 주기적 정합성 복구를 시도하지만, 노드 비정상 종료 등이 누적되면 노드 재활용/재부팅이 필요해집니다.
