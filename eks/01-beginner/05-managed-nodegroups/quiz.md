# 자가 점검 퀴즈

**Q1.** 노드그룹의 3층 구조와 각 층에서 확인할 수 있는 정보는?

**Q2.** "노드그룹 desired는 2인데 노드가 1개" — 진단 경로는?

**Q3.** ASG 소속 EC2를 직접 terminate하면 일어나는 일과, 그것이 "계획 교체"와 다른 점은?

**Q4.** AL2023과 Bottlerocket의 선택 기준을 3가지 관점에서 비교하세요.

**Q5.** "전용 풀"을 taint만으로 만들면 안 되는 이유와 완성 조건은? (k8s 34 연결)

**Q6.** Spot 풀 설계의 2대 원칙은?

**Q7.** updateConfig.maxUnavailable과 PDB의 관계는?

**Q8.** 노드 OS 패치가 "설치"가 아니라 "교체"인 이유와 그 운영 함의는?

---

## 정답

**A1.** ① EKS Nodegroup — 정책(AMI/타입/스케일/taint/업데이트 설정)과 health.issues ② ASG — 집행 활동 이력(충원 실패 사유가 여기) ③ EC2 — 실물 상태/시스템 로그(조인 실패). 진단은 위에서 아래로.

**A2.** nodegroup health.issues → ASG describe-scaling-activities(용량 부족/쿼터/서브넷 IP 고갈 등 실패 사유) → 떠 있는 EC2의 상태와 노드 조인 로그. 대부분 2층(ASG 활동 이력)에서 답이 나옵니다.

**A3.** ASG가 결원을 감지해 자동 충원하고, 죽은 노드의 Pod는 ReplicaSet이 재생성 — 인프라/워크로드 이중 자동 복구. 다른 점: drain이 없는 **급사**라 PDB가 못 지켜줍니다 — 계획 교체(update-nodegroup-version)는 cordon+drain으로 PDB를 존중합니다.

**A4.** 커스터마이즈: AL2023 유연(nodeadm) vs BR 제한(TOML). 보안 표면: AL2023 보통 vs BR 최소(패키지 매니저/셸 없음, 불변 루트). 운영: AL2023은 익숙한 리눅스 디버깅, BR은 admin 컨테이너 경유 — 보안 우선·표준 워크로드면 BR, 커스텀 요구면 AL2023.

**A5.** taint는 "밀어냄"일 뿐 — 아무 Pod나 toleration을 적으면 들어옵니다. 완성: taint + 대상 워크로드의 nodeSelector/affinity(끌어당김) + **admission 정책으로 toleration 사용 제한**(k8s 23/34) — 그래야 "전용"이 강제됩니다.

**A6.** ① 인스턴스 타입 다양화(한 타입 용량 고갈 대비) ② 중단 내성 워크로드만 입주(Job/멱등/PDB — k8s 20) + 가능하면 on-demand 폴백 경로.

**A7.** maxUnavailable은 **속도**(동시에 비울 노드 수), PDB는 **브레이크**(워크로드별 최소 가용성) — 업데이트는 둘의 교집합 속도로 진행되고, PDB가 빡빡하면 maxUnavailable이 커도 멈춥니다(k8s 35의 데드락).

**A8.** 불변 인프라 — 실행 중 노드를 변경하지 않고 새 AMI 노드로 갈아치워, 상태 드리프트 없이 전 노드가 동일 이미지가 됩니다. 함의: ① 패치 = update-nodegroup-version 트리거(분기 루틴, 자동 아님) ② 워크로드는 노드 교체 내성(PDB/graceful)이 필수 ③ 노드에 수동 설치한 것은 교체 때 증발 — 그래서 커스터마이즈는 템플릿/DaemonSet으로.
