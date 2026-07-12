# 자가 점검 퀴즈

**Q1.** EKS 청구서의 "숨은 3대장"과 각각의 구조적 원인·대책은?

**Q2.** Cost Explorer/CUR로 못 하는 것과, OpenCost가 그것을 하는 원리(배분 산식)는?

**Q3.** "k8s 비용의 단위는 requests다"를 스케줄러 동작으로 설명하세요.

**Q4.** 절감 사다리 5단의 순서와, ②→④ 순서를 어기면 생기는 일은?

**Q5.** requests 다이어트의 안전 공식과, 스냅샷 한 장으로 결정하면 안 되는 이유는?

**Q6.** OpenCost 출력의 `__idle__`과 `__unallocated__`가 각각 가리키는 문제와 처방은?

**Q7.** 고아 리소스 3종과 각각이 생기는 경로(앞 모듈 번호로)는?

**Q8.** 쇼백 루프가 완성되기 위한 세 부품과, 34가 미리 깔아둔 것은?

---

## 정답

**A1.** ① AZ 간 데이터 전송 — replica·LB cross-zone이 존을 넘나듦 → topology aware routing(14), 존 균형 배치. ② NAT GW 처리량 — Pod의 모든 외부 호출(ECR pull 포함) 통과 → S3/ECR VPC endpoint, keep-alive. ③ CloudWatch 수집 — 12의 debug 방치 유형 → retention·필터·IncomingBytes 알람.

**A2.** 한계: EC2 인스턴스 단위까지 — 한 노드 위 여러 팀 Pod의 몫을 못 나눕니다. OpenCost: 노드 단가를 **Pod의 max(requests, 실사용) 비율로 배분**하고 남는 몫을 idle로 분리 — ns/라벨(cost-center) 단위 금액이 나옵니다.

**A3.** 스케줄러는 실사용이 아니라 **requests 합**으로 노드의 빈자리를 계산합니다(k8s 06) — requests가 크면 실사용이 5%여도 그만큼의 노드가 존재해야 하므로, 노드 수(=비용)는 Σrequests의 함수입니다. 그래서 다이어트가 곧 노드 감소로 이어집니다(회수는 consolidation의 몫).

**A4.** 끄기 → right-sizing → bin-packing → 단가(Spot/Graviton/약정) → 아키텍처. ②(다이어트) 전에 ④의 약정을 맺으면 — 이후 줄인 용량만큼 약정이 남아 미사용 약정 손실("과체중을 3년 약정").

**A5.** requests = 피크 기간 포함 **p95 실사용 × 1.2~1.5**, 워크로드 하나씩 적용·관찰. 스냅샷 한 장은 시간대·요일·이벤트 변동을 못 담습니다 — 한산한 새벽 측정으로 조이면 피크에 스로틀·OOM으로 절감액보다 비싼 장애를 삽니다.

**A6.** `__idle__`: 어느 Pod에도 배분 안 된 노드 여백 — bin-packing 문제 → consolidation(17)·NodePool 리뷰. `__unallocated__`/라벨 없음: 소유자 불명 비용 — 라벨 규율 문제 → 테넌트 패키지(34)로 cost-center 강제, 신규 ns 라벨 필수화.

**A7.** ① 미부착 EBS — PVC 삭제 후 ReclaimPolicy/수동 볼륨 잔존(08·10). ② 유령 LB — Ingress/Service 삭제 실패·컨트롤러 죽음으로 잔존(08·14). ③ 무기한 로그 그룹·늙은 스냅샷 — retention/TTL 미설정(12·36).

**A8.** ① 계량기(OpenCost — 배분) ② 귀속 축(cost-center **라벨 규율** — 34의 테넌트 패키지가 ns 생성 시점에 강제해둔 것) ③ 정기 전달(월간 쇼백 표 + 권고). 셋이 돌면 requests 다이어트가 잔소리가 아니라 팀의 자발적 행동이 됩니다.
