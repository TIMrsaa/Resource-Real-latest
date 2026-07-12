# 이론 — 비용의 해부, 배분의 원리, 사다리의 각 단

> **🌱 17세 눈높이 비유: 아파트 관리비 정산**
> - **AWS 청구서** = 단지 전체 관리비 고지서 — 총액은 정확한데 **세대별 내역이 없습니다**
> - **OpenCost** = 세대별 계량기 — 각 집(네임스페이스)이 쓴 만큼을 배분해 보여줍니다
> - **requests** = 계약 평수 — 실제로 방 하나만 써도 **계약한 평수만큼** 관리비가 나옵니다 (k8s 비용의 단위는 사용이 아니라 예약!)
> - **고아 리소스** = 이사 가고 안 끊은 정수기 렌탈 — 아무도 안 쓰는데 매달 나갑니다
> - **Spot** = 경매 숙박(싸지만 주인이 2분 전 통보로 뺄 수 있음), **Savings Plans** = 장기 계약 할인(기준선에만), **on-demand** = 정가
> - **숨은 3대장** = 관리비 고지서의 "공용 전기·수도" — 엘리베이터(AZ 간 전송), 정문 경비(NAT), CCTV(관측 수집)

---

## 1. EKS 청구서 해부 — 노드 밖의 세계

| 항목 | 구조 | 함정 |
|------|------|------|
| Control plane | 클러스터당 시간 고정 | 유령 클러스터(dev 방치) |
| EC2 (노드) | 최대 항목 | requests가 결정 (§3) |
| EBS/EFS/스냅샷 | GB·월 | **고아 볼륨**(PVC 삭제 후 잔존), 스냅샷 무한 축적(36) |
| ELB | 시간+LCU | **유령 LB**(Ingress/Service 지운 뒤 잔존 — 14) |
| **데이터 전송** | AZ 간 GB당 | replica 간·cross-zone LB의 조용한 복리 (14·18) |
| **NAT GW** | 시간+처리 GB | Pod의 모든 외부 호출이 통과 — ECR pull까지! |
| **CloudWatch** | 수집 GB | 12의 그 폭탄 |

숨은 3대장(굵게)의 공통점: 설계 결정(어느 AZ에, 어떤 경로로, 무엇을 수집)이 요금이 되는 항목 — 나중에 줄이기 어렵고, **Cost Explorer에서 EC2가 아닌 줄**에 숨어 있습니다.

## 2. 가시화의 층 — 청구서에서 Pod까지

```
Cost Explorer   서비스·태그 단위 (어제까지, 그래프) — 출발점
CUR             시간·리소스 단위 원장 (Athena로 쿼리) — 정밀 조사
    ── 여기까지의 한계: EC2 인스턴스까지만. Pod/ns는 안 보인다 ──
OpenCost        노드 단가를 Pod의 requests 비율로 배분 + 유휴분 별도 표기
                → ns/라벨(cost-center — 34) 단위 금액
```

OpenCost의 배분 원리는 정직한 근사입니다: **Pod 비용 ≈ max(requests, 실사용) × 그 노드의 단가 비율** — 예약이 큰 Pod가 큰 비용을 배정받습니다(공정합니다 — 자리를 차지한 건 예약이니까). 남는 부분은 "idle"로 분리 표기 — 이 idle이 ③(bin-packing)의 표적입니다.

## 3. requests의 정치경제 — 예약이 곧 비용

```
노드 수 = f(Σ requests)   ← 스케줄러는 requests로 자리를 계산합니다 (k8s 06)
실사용 5%짜리 Pod라도 requests가 2 CPU면 → 2 CPU만큼의 노드가 존재해야 함
```

측정 지표: **갭 = requests − 실사용(p95)**. 갭 큰 워크로드 top N이 right-sizing의 우선순위입니다. 도구: `kubectl top`(즉석), VPA 추천 모드(지속 관찰 — 적용 말고 추천만), Prometheus 히스토리(15). 거버넌스: LimitRange 기본값(09)이 무지성 큰 requests를 막는 1차 댐, 쇼백(§5)이 문화적 2차 댐.

## 4. 사다리의 각 단 — 세부

- **① 끄기/지우기**: 고아 EBS(available 상태), 유령 LB, 오래된 스냅샷, 방치 로그 그룹(12), 유령 클러스터. 주기 스캔 스크립트(lab-01)를 cron으로 — 리스크 0의 공짜 점심
- **② right-sizing**: 갭 top N부터 — requests를 p95+여유로. 단 너무 조이면 스로틀/OOM(k8s 06) — "다이어트"지 "기아"가 아닙니다
- **③ bin-packing**: ②가 만든 잉여를 Karpenter consolidation(17)이 노드 수 감소로 회수 — ② 없이 ③만 켜면 회수할 잉여가 없습니다
- **④ 단가**: Spot(중단 내성 워크로드 — 17의 다양화 원칙), Graviton(19의 측정 후), Savings Plans — **기준선(24×7 최소 용량)에만**, Compute SP가 인스턴스 유연성 최고. 순서 규율: ②③이 끝나 몸무게가 확정된 뒤에 약정
- **⑤ 아키텍처**: topology aware routing(AZ 간 전송↓), VPC endpoint(S3/ECR — NAT 통과량↓), 관측 수집 통제(12), 이미지 다이어트(pull 전송↓)

## 5. 쇼백/차지백 — 피드백 루프의 완성

```
계량(OpenCost) → 월간 팀별 고지서(쇼백) → 팀이 자기 갭을 봄 → requests 다이어트가 자발적으로
```

쇼백(보여주기)까지가 플랫폼팀의 일, 차지백(실제 정산)은 조직 성숙도에 따라. 전제 조건이 **라벨 규율**입니다 — 34의 테넌트 패키지가 cost-center를 강제해둔 이유. 라벨 없는 워크로드는 "공용" 버킷에 쌓여 정산 분쟁의 씨앗이 됩니다.

## 6. 소스/도구에서 확인하기

- OpenCost(CNCF): https://github.com/opencost/opencost — 배분 명세(spec/) 자체가 좋은 교과서
- CUR: AWS 문서 "Cost and Usage Report" + Athena 연동
- AWS Compute Optimizer / Split Cost Allocation(EKS Pod 단위 CUR 분할 — OpenCost의 관리형 대안)
- Karpenter consolidation(17), VPA: kubernetes/autoscaler

## 요약 카드

| 질문 | 답 |
|------|----|
| 숨은 3대장? | AZ 간 전송, NAT GW 처리량, CloudWatch 수집 |
| CUR의 한계와 그 너머? | 인스턴스까지 — Pod/ns 배분은 OpenCost(requests 비율 배분) |
| k8s 비용의 단위? | 사용량이 아니라 **requests(예약)** — 갭 측정이 다이어트의 시작 |
| 사다리 순서? | 끄기 → right-sizing → bin-packing → 단가(약정은 마지막) → 아키텍처 |
| 약정의 규율? | 다이어트 후, 기준선에만, Compute SP 우선 |
| 문화적 완성? | 라벨 규율(34) → 쇼백 → 자발적 다이어트 루프 |
