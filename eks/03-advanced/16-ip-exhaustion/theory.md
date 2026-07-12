# 이론 — 소진 방정식과 세 단계 탈출구

> **🌱 17세 눈높이 비유: 아파트 단지 주차장**
> - **VPC 서브넷** = 단지 주차장, **Pod** = 입주민 차 — 차마다 실제 주차면(VPC IP)이 필요합니다
> - **warm pool** = 관리사무소(ipamd)가 각 동 앞에 **빈 자리를 미리 콘으로 막아두는** 습성 — 새 차가 오면 즉시 대주려고. 편하지만, 만석의 상당 부분이 "콘만 서 있는 자리"일 수 있습니다
> - **prefix delegation** = 주차면을 한 칸씩이 아니라 **16칸 구역 단위**로 배정 — 장부가 단순해지고 훨씬 많은 차를 받습니다. 단, 구역은 **연속된 16칸**이어야 합니다 — 듬성듬성 찬 낡은 주차장(파편화)에선 확보 실패
> - **secondary CIDR** = 옆 부지를 사서 **입주민 차 전용 주차장**을 새로 짓기 — 본 주차장은 관리 차량(노드/LB)만
> - **IPv6** = 번호판 체계를 바꿔 자리가 사실상 무한한 신도시로 이사 — 단, **이사지, 리모델링이 아닙니다** (기존 단지는 전환 불가)

---

## 1. 소진 방정식 — 고갈은 계산 가능한 미래입니다

```
서브넷의 공급:   AZ별 서브넷 크기 - AWS 예약(5개) - 노드/LB/기타 소비
Pod의 수요:      Σ 노드별 (실사용 Pod IP + warm pool 예약분)
잔여 Pod 예산 ≈  min(각 AZ 서브넷의 남은 IP)  ← ★ 고갈은 클러스터가 아니라 "서브넷(AZ) 단위"로 옵니다
```

세 가지 통찰:

1. **AZ 하나가 먼저 마릅니다** — 전체 합계가 여유로워도 한 AZ가 바닥이면 그 AZ의 노드에선 Pod가 안 뜹니다 (topology spread·LB가 그 AZ를 원하면 장애)
2. **warm pool은 수요를 부풀립니다** — 기본 `WARM_ENI_TARGET=1`은 노드마다 ENI 한 장 분량(수십 개 IP)을 선점합니다. 노드 수 × 수십 = "쓰지도 않는데 사라진 IP"
3. 자동 스케일(HPA→Karpenter)은 이 방정식의 소비 속도를 **곱셈으로** 올립니다

### 고갈의 증상 (진단 루틴 — 38 스타일)

```
Pod: ContainerCreating에서 정지
Events: "failed to assign an IP address to container" (CNI 플러그인 에러)
ipamd 로그(aws-node): "no available IP addresses" / assigned == total
AWS: describe-subnets의 AvailableIpAddressCount ≈ 0   ← 확진
```

## 2. 1단계 — warm 손잡이: 회수와 그 대가

| 설정 | 뜻 | 효과/대가 |
|------|----|----------|
| `WARM_ENI_TARGET=1` (기본) | 여분 ENI 1장 상시 | 스케일 순간 빠름 / IP 수십 개 선점 |
| `WARM_IP_TARGET=N` | 여분 IP N개만 | 선점 최소화 / Pod 급증 시 **EC2 API 호출이 경로에** — 기동 지연, API 쓰로틀 |
| `MINIMUM_IP_TARGET=M` | 바닥 보장 M | 기동 직후 안정 + WARM과 조합이 정석 |

원칙: **IP가 궁하면 WARM_IP_TARGET(+MINIMUM)으로 전환**해 선점을 회수하되, Pod 폭증 워크로드(배치, 이벤트)가 있으면 그만큼 기동이 느려짐을 수용해야 합니다 — 공짜 회수는 없습니다.

## 3. 2단계 — prefix delegation (07의 복습 + 함정 하나)

`ENABLE_PREFIX_DELEGATION=true`: ENI의 secondary IP 슬롯마다 개별 IP 대신 **/28 prefix(16개)** 를 붙입니다 → 노드당 밀도 수 배(max-pods 재계산 필요, 05). 함정: **/28은 연속 블록**이라 오래돼 파편화된 서브넷에선 할당 실패가 납니다 — "IP는 남았는데 prefix가 없다"는 신종 고갈. 새 서브넷/새 대역과 함께 쓸 때 가장 안전합니다 — 그래서 2단계와 3단계는 흔히 세트입니다.

## 4. 3단계 — secondary CIDR + custom networking (lab-02)

VPC에 두 번째 대역(관례: **100.64.0.0/10** — CG-NAT 대역, 사내망과 충돌 적음)을 붙이고, **Pod만 그리로 이주**시킵니다:

```
VPC: 10.0.0.0/16 (기존)  +  100.64.0.0/16 (신규 연결)
노드 primary ENI  → 기존 서브넷 (노드 IP, kubelet, LB 타깃 아님)
Pod용 secondary ENI → 신규 서브넷 (ENIConfig가 지정)

부품: ① associate-vpc-cidr-block  ② AZ별 Pod 서브넷
     ③ ENIConfig CRD (AZ별 — 서브넷+SG 지정)
     ④ aws-node env: AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
        + ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone (AZ 라벨로 자동 매칭)
     ⑤ ★ 새 노드부터 적용 — 기존 노드는 교체해야 이주
```

주의 두 가지: ① primary ENI를 Pod에 안 쓰게 되므로 **노드당 밀도가 오히려 줍니다** — prefix delegation 병행이 정석 ② 새 대역에 대한 라우팅/SG/NACL, 그리고 온프레미스 연결(VPN/DX)이 있다면 100.64 대역 충돌 검토.

## 5. 4단계 — IPv6: 다음 클러스터의 결정

- 노드마다 /80대의 prefix — Pod 주소가 사실상 무한, ipamd의 곡예(warm/prefix)가 통째로 사라집니다
- **클러스터 생성 시에만 선택 가능** — 기존 클러스터의 IPv4→IPv6 전환은 없습니다. 이건 마이그레이션 프로젝트(새 클러스터 + 워크로드 이사, 36/eks 23의 기술)입니다
- 바깥세상은 아직 IPv4: Pod(v6)→IPv4 목적지는 노드가 NAT로 이어주고, 유입은 dual-stack ALB/NLB가 받습니다 — "안은 v6, 경계는 이중언어"
- 체크리스트: 앱이 v6 리터럴/파싱에 무해한가, 온프레 연결의 v6 지원, 보안 도구의 v6 인지

## 6. 결정 트리

```
잔여 예산(lab-01) 몇 달치?
 ├ 충분 → warm 튜닝 + 알람(12)만 걸고 종료
 ├ 수 개월 → prefix delegation (새 서브넷이면 즉시, 파편화면 ②와 세트)
 ├ 임박/반복 → secondary CIDR + custom networking (+prefix)
 └ 신규 클러스터 계획 있음 → IPv6로 시작 (이 문제 자체를 졸업)
```

## 7. 소스/도구에서 확인하기

- amazon-vpc-cni-k8s: https://github.com/aws/amazon-vpc-cni-k8s — `pkg/ipamd/`(datastore, warm 로직), docs/eni-and-ip-target.md
- custom networking 공식 절차: EKS User Guide "CNI custom networking"
- IPv6 클러스터: EKS User Guide "IPv6 cluster" — 제약 표가 정직합니다
- max-pods 계산기: `max-pods-calculator.sh` (aws/amazon-vpc-cni-k8s)

## 요약 카드

| 질문 | 답 |
|------|----|
| 고갈의 단위? | 클러스터가 아니라 **AZ별 서브넷** — min()이 병목 |
| 보이지 않는 소비자? | warm pool (기본 ENI 1장 = 노드당 수십 IP 선점) |
| WARM_IP_TARGET의 대가? | Pod 급증 시 EC2 API가 기동 경로에 — 지연/쓰로틀 |
| prefix delegation 함정? | /28 연속 블록 필요 — 파편화 서브넷에서 실패 |
| custom networking 핵심? | ENIConfig(AZ별) + env 2개, **새 노드부터** + 밀도 하락 주의 |
| IPv6 최대 제약? | 신규 생성만 — 기존 클러스터는 이사(마이그레이션) 대상 |
