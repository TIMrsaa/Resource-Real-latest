# 자가 점검 퀴즈

**Q1.** skew 정책의 핵심 규칙 한 문장과, 그것이 업그레이드 순서를 강제하는 논리를 설명하세요.

**Q2.** control plane은 마이너 점프가 불가한데 노드는 가능한 이유는?

**Q3.** preflight 게이트 5가지(G1~G5)를 나열하세요.

**Q4.** 폐기 API 탐지에서 Pluto와 EKS insights의 사각지대는 각각 무엇인가요?

**Q5.** drain이 delete가 아니라 eviction API를 쓰는 것의 의미는?

**Q6.** `kubectl drain`이 건너뛰는 Pod 두 종류와 그 이유는?

**Q7.** "노드그룹 업그레이드가 몇 시간째 진행이 안 된다" — 첫 진단 명령과 예상 원인, 복구는?

**Q8.** 업그레이드 후 검증에서 "관측 스택 헬스"를 별도 항목으로 두는 이유는?

---

## 정답

**A1.** "어떤 컴포넌트도 kube-apiserver보다 신형일 수 없습니다." 노드를 먼저 올리면 kubelet > apiserver로 즉시 위반 — 그래서 CP를 먼저 올리고(노드가 뒤처지는 건 3마이너까지 합법) 노드가 따라가는 순서만 성립합니다.

**A2.** CP는 제자리 업그레이드라 1단계씩만. 노드는 업그레이드가 아니라 **새 버전 노드로의 교체**여서, 교체 후 상태가 skew만 만족하면(kubelet이 CP보다 ≤3 뒤 또는 동일) 구버전에서 몇 단계든 건너뛸 수 있습니다.

**A3.** G1 EKS insights(ERROR=중단), G2 폐기 API(Pluto 정적+insights 동적), G3 애드온 호환표(목표 버전 default 확보), G4 PDB 전수 점검(disruptionsAllowed=0 해소), G5 백업+공지+롤백 계획.

**A4.** Pluto(정적): 매니페스트가 아니라 **코드에서** 폐기 API를 호출하는 컨트롤러를 못 봅니다. insights(동적): 아직 배포되지 않은(런타임 호출이 없는) 매니페스트/차트를 못 봅니다. 사각이 정반대라 둘 다 돌립니다.

**A5.** eviction은 API 서버가 **PDB를 확인하고 거부(429)할 수 있는** 요청입니다(delete는 무조건 삭제). 이 거부권 덕분에 drain 중에도 가용성 하한이 기계적으로 지켜집니다 — 무중단 노드 교체의 근거.

**A6.** ① DaemonSet Pod — 노드마다 떠야 하는 존재라 옮길 곳이 없고, 노드 종료와 함께 사라지는 게 정상. ② static(mirror) Pod — kubelet이 직접 관리하므로 API로 축출해도 의미가 없습니다.

**A7.** `kubectl get pdb -A`로 ALLOWED DISRUPTIONS=0인 PDB 색출. 예상 원인: minAvailable=replicas(또는 replicas 부족)로 eviction이 전부 거부되는 데드락. 복구: replicas 증설 또는 PDB 완화(maxUnavailable:1) 후 재개.

**A8.** 업그레이드로 관측 스택이 죽으면 "조용함"이 정상처럼 보입니다 — 이후 실제 장애가 무관측 상태로 진행되는 2차 사고가 됩니다. "모든 게 보인다"까지 확인해야 업그레이드 종료입니다.
