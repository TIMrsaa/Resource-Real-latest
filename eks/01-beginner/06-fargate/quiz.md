# 자가 점검 퀴즈 (초급 트랙 졸업 시험 겸용)

**Q1.** Fargate의 실행 모델과 그것이 kubectl get nodes에 보이는 모습은?

**Q2.** Pod가 Fargate로 가는 경로를 webhook과 스케줄러 관점에서 설명하세요. (k8s 23/25 연결)

**Q3.** Fargate의 4대 제약과 각각의 근본 이유는?

**Q4.** "0.3 vCPU / 600Mi" 요청 Pod의 Fargate 과금 기준과 확인 방법은?

**Q5.** Fargate가 k8s 32의 격리 한계를 어떻게 해소하는지, lab의 증거와 함께 설명하세요.

**Q6.** Fargate 전용 클러스터에서 CoreDNS에 필요한 조치와 그 이유는?

**Q7.** (종합) ① 상시 웹 API ② EBS 쓰는 DB ③ 야간 배치 ④ 테넌트 코드 실행기 — 각각의 컴퓨팅 선택과 근거는?

**Q8.** (종합) 노드그룹/Auto Mode/Fargate에서 "노드 패치"가 각각 어떻게 처리되는가요?

---

## 정답

**A1.** Pod 1개 = Firecracker 마이크로VM 1개(커널 전용). get nodes엔 Pod마다 가상 노드(fargate-ip-...)가 하나씩 — Pod 수 = Fargate "노드" 수.

**A2.** Fargate 프로파일(ns+라벨 셀렉터)에 매칭되면 EKS의 **mutating webhook**이 Pod의 schedulerName을 fargate-scheduler로 변경(k8s 23의 변형 admission) → 기본 스케줄러 대신 **fargate-scheduler**(k8s 25의 멀티 스케줄러 패턴)가 VM을 프로비저닝해 배치. 매칭 실패 시 평소처럼 일반 노드로.

**A3.** ① DaemonSet 불가(설 노드가 없음) ② EBS 불가, EFS만(노드 수명=Pod 수명이라 블록 부착 부적합) ③ hostPath/hostNetwork/privileged 불가(호스트 개념 부재+보안 잠금) ④ GPU 미지원(+이미지 캐시 없음→콜드 스타트). 공통 근원: "공유되는 영속 노드"가 없습니다.

**A4.** requests 합을 지원 조합표로 **올림** — 0.3/600Mi → 0.5 vCPU/1GB 슬롯, 그 슬롯의 vCPU·초+GB·초로 과금. 확인: Pod의 `CapacityProvisioned` annotation.

**A5.** 컨테이너는 커널 공유(프로세스 격리)지만 Fargate는 Pod마다 전용 커널(VM 경계) — 탈출해도 이웃이 없습니다. 증거: Fargate Pod의 `/proc/uptime`이 Pod 나이와 비슷(이 커널은 이 Pod와 함께 태어남) vs 일반 노드 Pod는 노드의 긴 uptime.

**A6.** kube-system(또는 CoreDNS)을 매칭하는 Fargate 프로파일 + CoreDNS의 compute-type 어노테이션 조정 — 노드가 없으면 CoreDNS가 Pending이 되어 클러스터 DNS(k8s 16) 전멸이기 때문. "시스템 컴포넌트의 거처"는 컴퓨팅 전략의 일부입니다.

**A7.** ① Auto Mode(표준 기본값) 또는 노드그룹 ② 노드그룹/Auto Mode — EBS라서 Fargate 탈락 ③ Fargate(간헐 — Pod 과금 유리) 또는 Auto Mode+Spot ④ Fargate — VM 격리가 결정 요인.

**A8.** 노드그룹: **내가** update-nodegroup-version 트리거(AMI 교체 롤링 — 분기 루틴). Auto Mode: AWS가 최대 수명 내 자동 교체(나는 PDB로 견딜 준비). Fargate: AWS가 투명하게(필요시 재배포 권고) — 패치라는 일 자체가 위임 수준에 따라 사라져갑니다.
