# 자가 점검 퀴즈

**Q1.** IP 소진 방정식을 쓰고, "고갈은 서브넷(AZ) 단위로 온다"의 운영상 함의를 설명하세요.

**Q2.** "선점 IP − 실사용 Pod"의 간극은 무엇이며, 어느 설정들이 그 크기를 정하나요?

**Q3.** WARM_ENI_TARGET=1에서 WARM_IP_TARGET=3으로 바꾸면 얻는 것과 잃는 것은?

**Q4.** prefix delegation이 실패하는 서브넷의 조건과, 그 실패가 만드는 "신종 고갈"의 증상은?

**Q5.** custom networking의 다섯 부품을 순서대로 나열하고, "새 노드부터 적용"인 이유를 설명하세요.

**Q6.** custom networking을 켜면 노드당 max-pods가 왜 줄고, 표준 처방은 무엇인가요?

**Q7.** 100.64.0.0/10을 Pod 대역으로 고르는 이유와, 그럼에도 확인해야 할 충돌 지점은?

**Q8.** IPv6 클러스터의 가장 큰 제약과, "안은 v6, 경계는 이중언어"의 뜻은?

---

## 정답

**A1.** 잔여 Pod 예산 ≈ min(AZ별 서브넷 잔여 IP) − 노드 증설 시 warm 선점분. 함의: 합계 그래프는 안심시키는 거짓말일 수 있습니다 — 알람·용량 계획은 **AZ별 최솟값** 기준으로, 서브넷 크기는 AZ 간 균등하게.

**A2.** ipamd의 warm pool — 스케줄 순간 즉시 줄 IP를 미리 EC2에서 받아둔 것. 크기는 WARM_ENI_TARGET(기본 1 = ENI 한 장 분량), WARM_IP_TARGET, MINIMUM_IP_TARGET이 정하고, 노드 수에 비례해 클러스터 전체 선점량이 늡니다.

**A3.** 얻는 것: 노드당 선점이 ENI 한 장 분량(수십)에서 몇 개로 — 서브넷 여유 회복. 잃는 것: Pod가 한꺼번에 뜰 때 warm이 금방 바닥나 **EC2 API 호출이 기동 경로**에 들어옴 — 기동 지연, 대규모 스케일 시 API 쓰로틀 위험.

**A4.** 조건: 오래 써서 파편화된 서브넷 — /28 **연속 블록**이 없음. 증상: `AvailableIpAddressCount`는 수백인데 Pod는 IP 할당 실패로 ContainerCreating — "IP는 있는데 prefix가 없다". 처방: 깨끗한 새 서브넷(대개 secondary CIDR)과 함께 켜기.

**A5.** ① VPC에 secondary CIDR 연결 ② AZ별 Pod 서브넷 생성 ③ ENIConfig CRD(AZ명으로, 서브넷+SG) ④ aws-node env(CUSTOM_NETWORK_CFG + ENI_CONFIG_LABEL_DEF) ⑤ 새 노드 투입. 적용 시점이 "노드가 Pod용 secondary ENI를 **처음 만들 때**"라서 — 이미 ENI를 가진 기존 노드는 교체해야 이주됩니다.

**A6.** custom networking에선 primary ENI를 Pod에 쓰지 않으므로(노드 전용) ENI 예산이 한 장 줄어 max-pods가 감소. 표준 처방: **prefix delegation 병행** — 남은 ENI들의 슬롯마다 /28을 붙여 밀도를 몇 배로 회복 ("영토는 CIDR로, 밀도는 prefix로").

**A7.** 이유: CG-NAT 예약 대역이라 사내 10.x/172.16.x/192.168.x와 겹칠 확률이 낮고, VPC에 크게(/10 중 일부) 붙일 수 있습니다. 확인점: 온프레미스 방화벽/라우팅(VPN·DX 너머에서 Pod 발신 IP가 바뀜), 일부 통신사망·VPN 제품의 CG-NAT 사용과의 충돌, Pod IP를 하드코딩한 화이트리스트.

**A8.** 제약: **생성 시에만 선택** — 기존 클러스터 전환 불가, 원하면 새 클러스터로 이사 프로젝트. 이중언어: 클러스터 내부(Pod/Service)는 IPv6로 살고, 경계에서 — 유입은 dual-stack ALB/NLB가 v4 유저를 받아주고, 발신은 노드 NAT가 v4 목적지를 이어줍니다.
