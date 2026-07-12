# 자가 점검 퀴즈

**Q1.** CA와 Karpenter의 구조적 차이를 "스케일 단위"와 "EC2 호출 경로"로 설명하세요.

**Q2.** provisioning 파이프라인에서 "스케줄링 시뮬레이션"이 필요한 이유는?

**Q3.** NodePool과 EC2NodeClass의 역할 분담은? 각각에 들어가는 것 두 가지씩.

**Q4.** requirements의 "네거티브 설계"란 무엇이며, 좁힐 때 잃는 것 세 가지는?

**Q5.** consolidation의 delete와 replace를 구분하고, 각 판단의 근거를 설명하세요.

**Q6.** consolidation을 통제하는 세 손잡이와 각각의 사용 장면은?

**Q7.** spot 혼합 시 Karpenter가 2분 경고를 처리하는 경로와, 그 무중단성이 의존하는 k8s 부품들은?

**Q8.** "Karpenter 자신은 어디서 돌아야 하나" — 배치 원칙과 그 이유는?

---

## 정답

**A1.** CA: 스케일 단위가 **노드그룹(ASG)** — 미리 정의된 모양을 ASG desired 조정으로 늘림(간접, 분 단위). Karpenter: 단위가 **개별 노드** — Pending Pod 요구를 계산해 EC2 Fleet API를 직접 호출(groupless, 수십 초). "그룹을 스케일" vs "Pod에 노드를 맞춤".

**A2.** 노드를 만들기 **전에** "만들면 정말 이 Pod들이 스케줄되는가"를 보장해야 하므로 — affinity/taint/topology/PVC 존 같은 스케줄러의 제약 평가를 자체 재현해 가상 노드에 bin-packing해봅니다. 이게 틀리면 "노드는 떴는데 Pod는 여전히 Pending"이 됩니다.

**A3.** NodePool = k8s 쪽 정책: requirements(허용 타입 폭), taints, limits(예산), disruption(consolidation 정책·budgets), expireAfter. EC2NodeClass = AWS 쪽 디테일: AMI(alias), 노드 IAM role, subnet/SG selector(discovery 태그), 디스크 등.

**A4.** 안 되는 것만 배제하고(예: 4세대 이하 제외) 나머지를 열어두는 설계. 좁히면: ① 가격 최적화 여지 상실(후보 부족) ② 가용성 하락(그 타입 품절 시 대안 없음) ③ spot 중단 집중(분산 불가). 통제는 타입 지정이 아니라 limits/taint/budgets로.

**A5.** delete: 그 노드의 Pod 전부가 **기존 다른 노드들에** 들어갈 수 있을 때 — 노드 순삭제. replace: 통째로는 못 옮기지만 **더 싼 새 노드 1대**로 대체 가능할 때 — 새 노드 기동 → 이동 → 회수. 둘 다 "옮겨진다"를 스케줄링 시뮬레이션으로 검증한 뒤에만 실행.

**A6.** ① `karpenter.sh/do-not-disrupt`(Pod annotation) — 장시간 배치·상태 세션 보호. ② disruption.budgets — 동시 교체 폭·시간대 제한(이벤트 중 "0"). ③ consolidateAfter — 변화 후 관망 시간(출렁이는 워크로드의 노드 churn 방지).

**A7.** EC2 spot 중단 통지 → EventBridge → **SQS 인터럽션 큐** → Karpenter가 수신 즉시 해당 노드 cordon + drain + 대체 노드 준비. 무중단성의 의존 부품: replicas>1, **PDB**(19), preStop/graceful shutdown(14) — 2분 안에 정중히 이사할 수 있는 워크로드 설계.

**A8.** Karpenter(와 핵심 시스템 컴포넌트)는 **Karpenter가 만들지 않은 노드** — 작은 관리형 노드그룹(또는 Fargate) — 에서 돕니다. 자기가 만든 노드에 자기가 타면: 그 노드를 consolidation로 회수하는 순간 컨트롤러가 사라지는 닭-달걀 + 장애 시 노드를 만들 자가 없는 자기참조 붕괴.
