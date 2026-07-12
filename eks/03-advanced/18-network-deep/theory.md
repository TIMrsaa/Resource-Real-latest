# 이론 — 패킷 경로 4종, 검문소 3층, 그리고 CCTV의 사각

> **🌱 17세 눈높이 비유: 택배의 여행**
> - **Pod IP = VPC IP** — 이 단지의 택배는 **송장 주소를 바꿔 붙이지 않습니다**(오버레이 없음). 아파트 호수(Pod IP)가 곧 시 전체 지도에 있는 진짜 주소입니다
> - **veth** = 각 세대의 현관문 — 문 안쪽(Pod)과 바깥 복도(노드)를 잇는 한 쌍
> - **노드 라우팅 테이블** = 그 층의 안내판: "1004호(Pod IP)는 이 문(veth)으로"
> - **검문소 3층**: 단지 정문 경비(NACL — 나갈 때 들어올 때 **각각** 검사), 동 입구 경비(SG — 나간 사람의 **답장은 얼굴 기억으로 통과**), 각 세대의 문지기(NetworkPolicy — 집주인이 정한 방문자 명단)
> - **VPC Flow Logs** = 단지 CCTV — 누가 어디로 갔는지(메타데이터)는 다 찍지만, **세대 문 앞에서 문지기가 돌려보낸 것**은 복도 CCTV에 "도착"으로만 남습니다 (사각!)

---

## 1. 경로 ① — 같은 노드의 Pod → Pod

```
Pod A (netns A)                         Pod B (netns B)
  eth0 ── veth-A ──┐                ┌── veth-B ── eth0
                   ▼                ▲
              노드 라우팅 테이블: "B의 IP → veth-B" (host route)
```

- Pod 안의 라우팅은 단순합니다: 기본 게이트웨이 169.254.1.1(가상) → 전부 veth 밖으로
- 노드에는 **Pod IP마다 /32 host route**가 있습니다 — CNI가 Pod 생성 때 심는 안내판
- 같은 노드면 ENI/VPC로 나가지도 않습니다 — 노드 안 왕복 (최단 경로)

## 2. 경로 ② — 다른 노드의 Pod → Pod: "그냥 VPC"

```
Pod A → veth → 노드1 라우팅 → ENI(노드1) ──[VPC 라우팅]──▶ ENI(노드2, B의 IP를 secondary로 보유) → veth → Pod B
```

- 캡슐화 없음: 와이어 위의 패킷은 **src=A의 IP, dst=B의 IP 그대로** — VPC 입장에선 평범한 유니캐스트
- B의 IP는 노드2의 어떤 ENI에 secondary IP(또는 prefix)로 등록돼 있습니다(07) — VPC가 그 ENI로 배달
- 함의: Pod 간 트래픽에 **SG/NACL/FlowLogs가 그대로 적용**됩니다. 성능도 VPC 그 자체(터널 오버헤드 0)

## 3. 경로 ③ — Pod → VPC 밖 (인터넷/온프레)

- 기본: 노드를 떠나기 전 **SNAT** — src가 노드 primary IP로 바뀐 뒤 IGW/NAT GW로 (외부에서 보면 "노드가 보냈다")
- `AWS_VPC_K8S_CNI_EXTERNALSNAT=true`: SNAT 끄기 — 온프레(VPN/DX)에서 **Pod의 진짜 IP**를 봐야 할 때 (16의 100.64 이주와 자주 세트 — 방화벽 협의 필수)

## 4. 경로 ④ — 밖 → Pod (유입)

| 모드 | 경로 | 특징 |
|------|------|------|
| ALB target-type **ip** | ALB → **Pod ENI 직행** | kube-proxy 미경유 — 14의 세계 (readiness gate 필수인 이유) |
| target-type instance | ALB → NodePort → kube-proxy → Pod | 홉 +1, SNAT로 클라이언트 IP 소실 이슈 |
| NLB ip + client IP 보존 | NLB → Pod ENI | L4 직행 |

## 5. 검문소 3층 — 같은 차단, 다른 진실

| | NACL | Security Group | NetworkPolicy |
|---|---|---|---|
| 관할 | 서브넷 경계 | ENI | Pod (veth) |
| 상태성 | **stateless** — 응답도 규칙 필요 (ephemeral port 함정) | stateful — 응답 자동 | 정책 모델 (허용 목록) |
| 집행자 | VPC 라우터 | 하이퍼바이저 | **network-policy-agent의 eBPF** (노드 안) |
| Pod 단위? | ✘ (서브넷) | 기본은 노드 ENI 공유 (Pod별은 SG for Pods — branch ENI) | ✔ (라벨 선택) |
| 차단의 증거 | Flow Logs REJECT | Flow Logs REJECT | **Flow Logs에 안 남음** — agent 로그/메트릭 |

핵심 비대칭: **NP의 드롭은 ENI를 이미 통과한 뒤**(veth의 eBPF)에 일어납니다 — Flow Logs(ENI 관측)는 그 패킷을 ACCEPT로 기록합니다. "Flow Logs는 ACCEPT인데 안 간다" = NP(또는 그 위 계층)를 의심하라는 신호입니다.

> k8s 15와의 관계: NetworkPolicy **리소스**는 표준 그대로입니다 — 달라지는 건 집행자뿐(Calico 대신 VPC CNI의 aws-network-policy-agent, 애드온 설정 `enableNetworkPolicy`로 활성화 — 11의 configuration-values).

## 6. VPC Flow Logs — CCTV의 문법

ENI를 지나는 flow의 **메타데이터**(L3/4)를 기록합니다 — 페이로드는 없습니다:

```
srcaddr dstaddr srcport dstport protocol packets bytes action(ACCEPT/REJECT) ...
```

- 수준: VPC 전체 / 서브넷 / ENI 단위로 켤 수 있고, 목적지는 CW Logs(12의 세계) 또는 S3(+Athena)
- REJECT의 의미: **SG 또는 NACL이 막았습니다** (NP 아님 — §5)
- 활용: top talker, 예상 밖 목적지(보안), "그 시각 그 포트에 REJECT가 있었나"(진단), AZ 간 트래픽 비용 추적(14 cross-zone)
- 비용: 수집량 과금 — 상시 전체 켜기보다 조사 기간·대상 한정이 현실적 (12의 규율 그대로)

## 7. 진단 계단 — "A에서 B로 안 가요"

```
0. 이름부터: DNS가 되나요? (nslookup B — 안 되면 16 CoreDNS 문제, 네트워크 아님)
1. NetworkPolicy: B의 ns에 정책 있나요? A가 허용 목록에 있나요? (kubectl get netpol)
2. SG: B가 있는 노드(또는 Pod SG)의 인바운드가 그 포트를 허용하나요?
3. NACL: A와 B가 다른 서브넷이면 — 양방향 + ephemeral port까지?
4. 라우팅: 같은 VPC인가요? 피어링/TGW면 라우트 테이블에 상대 CIDR이 있나요?
5. 증거: Flow Logs — REJECT면 SG/NACL 확정, ACCEPT인데 불통이면 1번(NP) 재심문
```

위(앱에 가까운 층)에서 아래로 — 확률도 대개 그 순서입니다.

## 8. 소스/도구에서 확인하기

- aws-network-policy-agent: https://github.com/aws/aws-network-policy-agent — eBPF 프로그램과 정책 평가
- VPC CNI 라우팅 설정부: amazon-vpc-cni-k8s `cmd/routed-eni-cni-plugin/` (veth·host route를 심는 그 코드 — 29의 무대)
- Flow Logs 필드 명세: AWS 문서 "Flow log records"
- `kubectl debug node` 문서 — 노드 진단의 표준 통로

## 요약 카드

| 질문 | 답 |
|------|----|
| VPC CNI 제1원리? | Pod IP = VPC IP — 오버레이 없음 (성능·AWS 도구 일원화·IP 소비) |
| 노드가 Pod를 찾는 법? | Pod IP마다 /32 host route → veth |
| Pod→외부의 기본? | 노드 IP로 SNAT (EXTERNALSNAT로 끌 수 있음 — 온프레 협의) |
| 검문소 3층? | NACL(stateless/서브넷) · SG(stateful/ENI) · NP(eBPF/Pod) |
| Flow Logs의 사각? | NP 드롭 — ENI에선 ACCEPT로 보임 |
| 진단 순서? | DNS → NP → SG → NACL → 라우팅 → Flow Logs 증거 |
