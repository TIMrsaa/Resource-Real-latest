# 자가 점검 퀴즈

**Q1.** "VPC CNI는 오버레이가 없다"에서 따라 나오는 결과 세 가지(성능/도구/비용)는?

**Q2.** Pod 안의 라우팅 테이블과 노드의 host route는 각각 어떤 모양이며, 누가 언제 만드나요?

**Q3.** 다른 노드의 Pod로 가는 패킷이 와이어 위에서 갖는 src/dst는? 오버레이 CNI와의 차이는?

**Q4.** 검문소 3층의 관할·상태성·집행자를 표로 정리하세요.

**Q5.** "Flow Logs엔 ACCEPT인데 통신이 안 된다" — 이 증상이 지목하는 용의자와 그 이유는?

**Q6.** NACL의 stateless가 만드는 대표적 함정 시나리오는?

**Q7.** Pod의 발신이 밖에서 어떤 IP로 보이는지 — 기본 경로와, 그것을 바꾸는 두 가지 설정 변화는?

**Q8.** 진단 계단 6단계를 순서대로 쓰고, "위에서 아래로"인 이유를 설명하세요.

---

## 정답

**A1.** ① 성능: 캡슐화/터널 홉이 없어 Pod 간 통신이 VPC 네이티브 속도. ② 도구: SG·NACL·Flow Logs 등 AWS 네트워크 도구가 Pod 트래픽에 그대로 적용(관측·보안 일원화). ③ 비용: Pod마다 진짜 VPC IP를 소비 — 16(IP 고갈)의 근원.

**A2.** Pod 안: `default via 169.254.1.1 dev eth0` 한 줄(전부 veth 밖으로 — 지능 없음). 노드: **Pod IP마다 /32 host route → 해당 veth** — CNI 플러그인(routed-eni)이 Pod 생성 시점에 심습니다.

**A3.** src=발신 Pod IP, dst=수신 Pod IP **그대로** — 재작성·캡슐화 없음, VPC 입장에선 평범한 유니캐스트(수신 Pod IP는 상대 노드 ENI의 secondary IP). 오버레이 CNI라면 노드 IP끼리의 터널 패킷 안에 원본이 캡슐화되어 VPC는 Pod IP를 모릅니다.

**A4.** NACL: 서브넷 경계 / stateless(왕복 각각) / VPC 라우터. SG: ENI / stateful(응답 자동) / 하이퍼바이저. NetworkPolicy: Pod(veth) / 허용 목록 모델 / **aws-network-policy-agent의 eBPF**(노드 안).

**A5.** NetworkPolicy(또는 그 위 — 앱 미기동, 프로세스 포트 불일치). Flow Logs는 ENI 관문 기록인데 NP 드롭은 ENI 통과 **후** veth의 eBPF에서 일어나므로 CCTV엔 ACCEPT로 남습니다. REJECT만 SG/NACL의 확정 증거입니다.

**A6.** 인바운드 요청 포트만 열고 **아웃바운드 ephemeral port(응답 경로)** 를 안 연 경우 — SYN은 도착하는데 응답이 차단돼 "간헐 타임아웃"처럼 보입니다. stateful인 SG 감각으로 NACL을 다루다 생기는 사고.

**A7.** 기본: 노드에서 SNAT(노드 primary IP) → (사설 서브넷이면) NAT GW의 EIP로 한 번 더 — 밖에선 NAT GW IP. 바꾸는 것: ① `AWS_VPC_K8S_CNI_EXTERNALSNAT=true`(SNAT 끔 — 온프레에 Pod 실주소 노출) ② 16의 secondary CIDR 이주(발신 대역 자체가 100.64로) — 둘 다 방화벽 협의가 선행돼야 합니다.

**A8.** ⓪ DNS → ① NetworkPolicy → ② SG → ③ NACL → ④ 라우팅 → ⑤ Flow Logs 증거 대조. 위층일수록 앱에 가깝고 변경 빈도가 높아 **범인일 확률이 높으며**, 확인 비용도 쌉니다(kubectl 한 줄 vs 네트워크 팀 소환) — 확률과 비용 순의 심문이 가장 빨리 끝납니다.
