# 자가 점검 퀴즈

**Q1.** maxPods 기본 공식과 t3.medium/m5.large의 값은?

**Q2.** ipamd의 warm pool이 주는 것과 빼앗는 것은?

**Q3.** Pod 생성 시 IP가 "즉시" 나오는 경우와 "느린" 경우의 분기는?

**Q4.** prefix delegation의 동작, 효과, 그리고 2가지 전제 조건은?

**Q5.** "프리픽스 켰는데 노드당 Pod 수가 그대로" — 원인 2가지는?

**Q6.** vpc-cni 환경변수를 바꾸는 올바른 통로와, kubectl set env의 문제는?

**Q7.** SG-for-Pod와 NetworkPolicy의 분업은?

**Q8.** IP 고갈을 장애 전에 잡는 관측 항목 3가지는?

---

## 정답

**A1.** maxPods = ENI수 × (ENI당 IP − 1) + 2. t3.medium: 3×5+2=**17**, m5.large: 3×9+2=**29**. CPU/메모리보다 먼저 닿는 천장.

**A2.** 주는 것: Pod 기동 속도(미리 확보한 IP 즉시 지급 — EC2 API 대기 없음). 빼앗는 것: 서브넷 IP를 안 쓰면서 선점(잠식) — 좁은 서브넷에서 고갈을 앞당깁니다. WARM_* 변수로 균형 조절.

**A3.** 풀에 여분 IP가 있으면 즉시(로컬 장부에서 지급). 풀이 비었으면 ipamd가 EC2 API로 ENI/IP를 추가하는 동안 대기 — 스파이크 때 Pod 기동 지연의 원인. (서브넷까지 비었으면 실패 — 고갈)

**A4.** ENI에 secondary IP 낱개 대신 **/28 프리픽스(16개 묶음)**를 붙임 — 같은 ENI 슬롯으로 밀도 ×16, EC2 API 호출도 묶음 단위로 감소. 전제: ① 니트로 인스턴스 ② 서브넷에 **연속된 /28 블록** 존재(파편화 시 InsufficientCidrBlocks).

**A5.** ① kubelet maxPods를 안 올림(슬롯은 있는데 kubelet이 거절) ② 기존 노드에서 확인함(부팅 시 결정 — 새 노드부터 적용). +③ 서브넷 파편화로 프리픽스 할당 실패 중일 수도(ipamd 로그).

**A6.** 관리형 애드온의 configuration-values(`aws eks update-addon`)가 진실의 원천. set env 직접 수정은 다음 애드온 업데이트가 **조용히 원복** — "어느 날 꺼져 있는" 사고의 원인(11의 주제).

**A7.** SG-for-Pod: Pod→**VPC 자원**(RDS/ElastiCache 등) 접근을 AWS SG로 정밀 제어 — branch ENI 소비, 소수 Pod에만. NetworkPolicy: **Pod↔Pod** 트래픽 제어(k8s 15) — 클러스터 내부의 표준. 둘은 대체가 아니라 보완.

**A8.** ① ipamd 메트릭 awscni_total/assigned_ip_addresses(노드 재고와 할당률) ② 서브넷 AvailableIpAddressCount(잔량 임계 알림) ③ ipamd 로그의 실패 시그니처(`failed to assign an IP`, `InsufficientCidrBlocks`).
