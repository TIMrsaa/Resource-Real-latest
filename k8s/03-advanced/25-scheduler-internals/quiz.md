# 자가 점검 퀴즈

**Q1.** 스케줄링 사이클이 직렬이고 바인딩 사이클이 병렬인 이유를 각각 쓰라.

**Q2.** Reserve 단계가 없다면 발생할 수 있는 문제는?

**Q3.** `0/5 nodes are available: 3 Insufficient memory, 2 node(s) had untolerated taint` — 각 사유를 담당 플러그인과 사용자가 고칠 YAML 위치로 매핑하세요.

**Q4.** "노드에 자리가 났는데 Pending Pod가 수 초 후에야 뜨는" 이유는?

**Q5.** LeastAllocated와 MostAllocated의 트레이드오프를 비용/가용성 관점에서 설명하세요.

**Q6.** EKS에서 스케줄링 성향을 바꾸고 싶을 때의 방법과, 그때 Pod가 해야 할 일은?

**Q7.** schedulerName에 오타가 있는 Pod의 증상은? (이벤트 관점)

**Q8.** Karpenter는 kube-scheduler를 대체하는가요? 둘의 분업을 설명하세요.

---

## 정답

**A1.** 직렬: 두 Pod가 동시에 같은 자원을 "본인 것"으로 계산하는 일관성 붕괴를 막기 위해. 병렬 바인딩: binding은 API 왕복(수십 ms~)이라, 그걸 기다리면 처리량이 무너지므로 결정만 끝나면 비동기로 넘깁니다.

**A2.** 바인딩(비동기)이 끝나기 전의 노드 자원이 캐시에 "빈 것"으로 보여, 다음 Pod 결정이 **같은 자원을 이중 배정**할 수 있습니다. Reserve가 캐시에 선점 기록을 남겨 방지합니다.

**A3.** Insufficient memory → **NodeResourcesFit** → Pod의 `resources.requests`(낮추거나 노드 증설). untolerated taint → **TaintToleration** → Pod의 `tolerations` 추가(또는 taint가 의도인지 확인).

**A4.** 스케줄 실패 Pod는 **backoffQ**에서 지수 백오프(최대 ~10s) 대기 후 재시도되기 때문. 즉시 재시도는 실패 폭주를 만들므로 의도된 설계입니다.

**A5.** LeastAllocated(기본, spreading): 노드 장애 폭발 반경이 작고 버스트 여유가 있으나 노드가 줄지 않아 **비용 비효율**. MostAllocated(bin-packing): 빈 노드를 만들어 회수 가능(**비용 절감**)하나 노드당 밀도가 높아 장애/회수 시 충격이 큽니다 — spread 제약·PDB와 병행 필수.

**A6.** 기본 스케줄러 설정은 관리형이라 불가 → **커스텀 설정의 두 번째 스케줄러를 Deployment로 배포** (KubeSchedulerConfiguration + RBAC). Pod는 `spec.schedulerName`으로 그 스케줄러를 지정해야 합니다.

**A7.** 그 이름의 스케줄러가 없으면 어떤 스케줄러도 그 Pod를 담당하지 않아 — **이벤트조차 없는 영구 Pending** (FailedScheduling도 안 찍힘).

**A8.** 대체하지 않습니다. **kube-scheduler = Pod를 기존 노드에 배치**, **Karpenter = 배치 불가능한(Pending) Pod를 보고 알맞은 노드를 새로 공급**(+빈 노드 회수). Karpenter가 만든 노드에 실제 배치하는 것도 kube-scheduler입니다.
