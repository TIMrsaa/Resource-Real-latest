# 자가 점검 퀴즈

**Q1.** 표준 EKS 대비 Auto Mode가 추가로 가져가는 것 5가지는?

**Q2.** Auto Mode 노드에서 kube-system이 한산한 이유는?

**Q3.** Auto Mode의 대가(트레이드오프) 3가지는?

**Q4.** "Pod를 만들었더니 노드가 태어났다" — 이 흐름을 이벤트 레벨로 설명하세요.

**Q5.** NodePool의 limits가 막는 사고와 표준 모드에서의 대응물은?

**Q6.** Auto Mode 입주 전 워크로드가 갖춰야 할 조건 3가지와 그 이유(21일 규칙)는?

**Q7.** 내장 EBS 프로비저너 이름이 표준과 다른 것이 마이그레이션에서 의미하는 바는?

**Q8.** Auto Mode가 부적합한 시나리오 3가지는?

---

## 정답

**A1.** ① 노드 프로비저닝(내장 Karpenter) ② 노드 OS 패치/교체(최대 수명 내 자동 롤링) ③ 핵심 애드온(CNI/CoreDNS/kube-proxy — 노드 내장화) ④ EBS CSI 컨트롤러 ⑤ ALB/LB 컨트롤러. (+OS는 Bottlerocket 고정)

**A2.** VPC CNI와 kube-proxy 등이 DaemonSet Pod가 아니라 **노드 내장 프로세스(systemd)** 로 돌기 때문 — kubelet과 같은 지위로 들어갔습니다. 컨트롤러류(Karpenter, EBS/ALB)는 AWS 쪽 관리 영역에서 돕니다.

**A3.** ① 관리 수수료(EC2 요금에 추가) ② 노드 접근 불가(SSH/SSM/debug 제한 — 노드 층 디버깅 소멸) ③ 커스터마이즈 제한(커스텀 AMI/호스트 데몬 불가, OS 고정) + 최대 수명에 의한 강제 교체.

**A4.** Pod 생성 → 스케줄러가 배치 실패(Pending — 맞는 노드 없음) → 내장 Karpenter가 그 Pod의 요구사항(리소스/셀렉터/톨러레이션)을 읽어 NodeClaim 생성 → EC2 기동(~1분대) → 노드 Ready → 스케줄러가 배치 → Running. 수요가 사라지면 consolidation이 빈 노드를 회수.

**A5.** HPA 폭주/replicas 실수가 인스턴스를 무한 생성하는 비용 사고 — limits는 그 풀의 총 자원 상한. 표준 모드의 대응물은 노드그룹 maxSize.

**A6.** ① PDB(축출 속도 제한) ② graceful shutdown(SIGTERM/preStop) ③ 상태 외부화(PVC/외부 저장소) — 최대 수명(기본 21일) 안에 **모든 노드가 반드시 교체**되므로, 교체를 못 견디는 워크로드는 주기적으로 죽습니다.

**A7.** 내장은 `ebs.csi.eks.amazonaws.com`, 자가 설치 표준은 `ebs.csi.aws.com` — 기존 StorageClass를 그대로 못 쓰고 새 클래스를 만들어야 하며, 병행 기간엔 "어느 드라이버가 어느 클래스를 집행하나"를 명시적으로 분리해야 합니다.

**A8.** ① 커스텀 AMI/커널/호스트 설치형 에이전트 요구 ② 노드 직접 접근이 필수(규제/특수 디버깅) ③ 특수 GPU 구성 등 지원 밖 하드웨어, 그리고 ④ 거대 규모에서 관리 수수료가 직접 Karpenter 운영 비용을 넘는 경우.
