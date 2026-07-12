# 자가 점검 퀴즈

**Q1.** 컨테이너 쓰기 레이어 / emptyDir / PVC 각각의 데이터 수명을 비교하세요.

**Q2.** PV, PVC, StorageClass의 역할을 "사람"으로 비유해 설명하세요.

**Q3.** ReadWriteOnce에서 "Once"의 단위는? 이로 인해 생기는 대표적 에러는?

**Q4.** WaitForFirstConsumer가 푸는 문제를 시나리오로 설명하세요.

**Q5.** PVC를 만들었는데 Pending입니다. 정상인 경우와 비정상인 경우를 구분하는 법은?

**Q6.** PVC 쓰는 Deployment에 `strategy: Recreate`를 권하는 이유는?

**Q7.** "디스크가 가득 차서 줄이고 다시 늘리려" 합니다. 가능한 것과 불가능한 것은?

---

## 정답

**A1.** 쓰기 레이어: **컨테이너 재시작이면 소멸.** emptyDir: 컨테이너 재시작엔 생존, **Pod 삭제 시 소멸.** PVC: Pod와 무관하게 **PVC(와 reclaimPolicy)가 수명을 결정.**

**A2.** PVC = 개발자의 "사물함 신청서"(크기/등급만 명시), StorageClass = 인프라팀의 "메뉴판 + 주문처 정보"(타입/암호화/확장 정책), PV = 시스템이 만들어 배정한 "실물 사물함".

**A3.** **노드** 단위 (Pod 아님). 같은 노드의 여러 Pod는 공유 가능. 다른 노드의 Pod가 붙으려 하면 `Multi-Attach error`.

**A4.** Immediate면 PVC 생성 즉시 임의 AZ(2a)에 EBS 생성 → Pod가 2c에 스케줄되면 AZ 종속인 EBS가 못 붙어 영원히 Pending. WFFC는 **Pod 스케줄 후 그 노드의 AZ에** 볼륨을 만들어 해결.

**A5.** describe 이벤트 확인: "waiting for first consumer"면 **정상**(Pod 생기면 풀림). provisioner 에러/권한 에러가 찍혀 있으면 비정상(CSI 드라이버/IAM 점검).

**A6.** RollingUpdate는 신구 Pod가 잠시 공존하는데, RWO 볼륨은 동시에 두 노드에 못 붙어 **서로 기다리는 교착**이 생깁니다. Recreate는 옛 Pod를 먼저 죽여 볼륨을 풀어줍니다 (짧은 다운타임 감수).

**A7.** 확장(2Gi→10Gi)은 온라인으로 가능(`allowVolumeExpansion`). **축소는 불가능** — 새 PVC를 만들어 데이터를 옮기는 수밖에 없습니다.
