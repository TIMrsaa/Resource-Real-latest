# 이론 — provisioning 파이프라인, NodePool 설계, consolidation의 산수

> **🌱 17세 눈높이 비유: 버스 노선 증차 vs 콜택시 배차**
> - **Cluster Autoscaler** = 버스 회사: 노선(노드그룹)마다 같은 크기의 버스. 승객이 넘치면 "그 노선에 버스 한 대 더" — 어떤 버스일지는 **미리 정해져 있습니다**
> - **Karpenter** = 콜택시 배차 시스템: 대기 승객(Pending Pod)들의 인원·짐·목적지를 보고 "이 조합이면 6인승 한 대가 최적"을 **그 자리에서 계산**해 부릅니다
> - **NodePool** = 배차 규칙서: "우리는 이런 차종만(계열), 이 요금제(spot/on-demand), 월 예산 한도(limits)" — 규칙이 관대할수록 배차가 싸고 빠릅니다
> - **consolidation** = 손님이 내린 뒤: 텅 빈 대형차는 돌려보내고(delete), 두 명 남은 대형차는 소형차로 갈아태웁니다(replace)
> - **do-not-disrupt** = "이 손님은 수술 중 — 절대 갈아태우지 마세요" 스티커

---

## 1. 구조 비교 — 왜 다시 만들었나

| | Cluster Autoscaler | Karpenter |
|---|---|---|
| 단위 | 노드그룹(ASG) — **미리 정의된 모양** | groupless — 노드를 개별 생성 |
| 경로 | ASG desired 조정 → ASG가 EC2 생성 | **EC2 Fleet API 직접 호출** |
| 타입 선택 | 그룹에 박힌 타입 | 매번 수백 타입 중 계산 |
| 속도 | 분 단위 (ASG 경유) | 수십 초 (직접 + 병렬) |
| bin-packing | 그룹 크기에 맞추는 수동 설계 | Pod 조합 기반 자동 |
| 축소 | 사용률 임계 기반 | 시뮬레이션 기반 consolidation |

핵심 차이 하나로 요약하면: CA는 **그룹을 스케일**하고, Karpenter는 **Pod에 노드를 맞춥니다.**

## 2. provisioning 파이프라인 해부

```
① 감지    Pending Pod watch (스케줄 실패 이벤트)
② 시뮬레이션  kube-scheduler와 같은 제약 평가를 자체 수행:
           requests 합산, nodeSelector/affinity, taint/toleration,
           topologySpreadConstraints, PVC 존(10) ...
           → Pod들을 "가상 노드"에 bin-packing
③ 타입 산정  가상 노드를 만족하는 인스턴스 타입 후보 목록
           (NodePool requirements로 필터 — 남은 후보가 많을수록 유리)
④ 주문     EC2 Fleet에 후보 목록째 요청 — 가격·가용성 최적(spot이면
           price-capacity-optimized)을 AWS가 낙찰
⑤ NodeClaim  "노드 하나의 생애"를 추적하는 CRD — EC2 기동 → 조인 →
           Ready → (훗날) 회수까지 이 객체가 대변합니다
⑥ 배치     노드 Ready → 스케줄러가 Pending Pod를 바인딩
```

②가 존재하는 이유: 노드를 **만들기 전에** "만들면 정말 스케줄되는가"를 알아야 합니다 — Karpenter는 스케줄러의 판단을 미리 흉내 내는 시뮬레이터를 품고 있습니다 (affinity가 복잡할수록 이 시뮬레이션이 일을 합니다).

## 3. API 두 장 — NodePool과 EC2NodeClass

```yaml
# NodePool — "어떤 노드를 허락하나" (k8s 쪽 언어)
apiVersion: karpenter.sh/v1
kind: NodePool
spec:
  template:
    spec:
      requirements:                                  # ★ 폭이 곧 성능
      - { key: karpenter.k8s.aws/instance-category, operator: In, values: [c, m, r] }
      - { key: karpenter.k8s.aws/instance-generation, operator: Gt, values: ["4"] }
      - { key: karpenter.sh/capacity-type, operator: In, values: [on-demand, spot] }
      - { key: kubernetes.io/arch, operator: In, values: [amd64, arm64] }
      nodeClassRef: { group: karpenter.k8s.aws, kind: EC2NodeClass, name: default }
      taints: []                                     # 특수 풀이면 여기 (34의 격리 문법)
      expireAfter: 720h                              # 노드 수명 상한 — 자연 순환(35의 AMI 최신화)
  limits: { cpu: "100" }                             # 이 풀의 총 예산 상한
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
    budgets: [{ nodes: "10%" }]                      # 동시 교체 폭
---
# EC2NodeClass — "AWS 쪽 디테일" (AMI/서브넷/SG/역할)
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
spec:
  amiSelectorTerms: [{ alias: al2023@latest }]       # AMI 계열 (05의 그 선택)
  role: KarpenterNodeRole-<cluster>
  subnetSelectorTerms: [{ tags: { karpenter.sh/discovery: <cluster> } }]
  securityGroupSelectorTerms: [{ tags: { karpenter.sh/discovery: <cluster> } }]
```

**requirements 설계의 역설**: 타입을 좁게 못 박을수록(통제욕) ③의 후보가 줄어 — 비싸지고, spot이면 중단도 잦아집니다. 정석은 **네거티브 설계**: "안 되는 것만 배제"(예: 5세대 미만 제외, t 계열 제외)하고 나머지는 열어둡니다.

## 4. consolidation — 되감기의 산수

Karpenter는 주기적으로 "지금 클러스터를 더 싸게 재구성할 수 있나"를 시뮬레이션합니다:

| 액션 | 조건 | 예 |
|------|------|----|
| **delete** | 노드의 Pod 전부가 다른 노드에 들어감 | 빈 노드, 스케일다운 후 잔반 노드 |
| **replace** | 더 싼 노드 1대로 대체 가능 | 8xlarge에 Pod 두 개 → large로 교체 |

안전장치들 (전부 35의 언어로 이해됩니다):

- 이동은 **eviction 경유 — PDB 존중** (19·35). PDB가 막으면 consolidation도 멈춥니다
- `karpenter.sh/do-not-disrupt: "true"` (Pod annotation) — 그 Pod가 있는 노드는 자발적 중단 금지 (배치 작업·상태 세션)
- `disruption.budgets` — "동시에 몇 노드까지" (예: 10%, 야간만 허용 같은 스케줄도 가능)
- `consolidateAfter` — 변화 후 관망 시간 (출렁이는 워크로드에서 노드 churn 방지)

**spot 노드의 replace는 보수적**입니다 — "더 싼 spot으로 교체"를 무한 반복하면 중단 위험만 쌓이므로, 후보가 충분히 많을 때만(15개 이상 저렴한 타입) spot→spot 교체를 허용하는 휴리스틱이 들어 있습니다.

## 5. Spot과 중단 처리

- NodePool에 `capacity-type: [spot, on-demand]`를 함께 열면 — spot 가능하면 spot, 안 되면 od로 자연 폴백
- **2분 경고**: EC2 spot 중단 통지 → (EventBridge→SQS 인터럽션 큐) → Karpenter가 즉시 cordon+drain — PDB·preStop(14)이 여기서도 무중단의 부품이 됩니다
- 어울리는 워크로드: 무상태·재시도 가능(웹 replicas, 배치). 금물: 단일 인스턴스 상태 저장 — 그건 od + do-not-disrupt

## 6. 설계 패턴 3종

```
① 범용 풀 (weight 낮음): 넓은 requirements + spot/od — 대부분의 워크로드
② 특수 풀: GPU(19), 컴플라이언스(od 전용), 테넌트 전용(taint — 34의 노드 격리를
   Karpenter가 자동 운영) — 좁은 requirements + 명시적 taint
③ 안전핀: 풀마다 limits(cpu/memory 총량) = 폭주 시 청구서 상한
           expireAfter = AMI/커널의 자연 순환 (35의 노드 교체가 상시 자동화되는 셈)
```

## 7. 소스/도구에서 확인하기

- 코어(중립부): https://github.com/kubernetes-sigs/karpenter — `pkg/controllers/provisioning/scheduling/`(시뮬레이터), `pkg/controllers/disruption/`(consolidation)
- AWS 프로바이더: https://github.com/aws/karpenter-provider-aws — `pkg/providers/instancetype/`(타입 산정) — **29(기여 모듈)의 무대**
- NodePool API 레퍼런스: https://karpenter.sh/docs/concepts/nodepools/

## 요약 카드

| 질문 | 답 |
|------|----|
| CA와의 본질 차이? | 그룹을 스케일 vs **Pod에 노드를 계산해 맞춤** (groupless, EC2 직접) |
| 파이프라인? | Pending → 스케줄 시뮬레이션 → 타입 후보 → Fleet 주문 → NodeClaim |
| requirements 정석? | 네거티브 설계 — 배제만 하고 열어둡니다 (후보 폭 = 가격·속도·안정) |
| consolidation 두 액션? | delete(재배치 가능) / replace(더 싼 1대로) — 전부 시뮬레이션 기반 |
| 통제 3종? | do-not-disrupt(Pod), budgets(동시 폭), consolidateAfter(관망) |
| 노드 위생? | expireAfter로 수명 상한 — AMI 순환이 상시 자동화 |
| 예산 안전핀? | NodePool limits — 자동화의 청구서 상한 |
