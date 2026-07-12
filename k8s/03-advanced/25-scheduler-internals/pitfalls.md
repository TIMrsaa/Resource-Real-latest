# 흔한 함정 5선

## 1. 존재하지 않는 schedulerName

`spec.schedulerName: cost-scheduler`를 적었는데 그 스케줄러가 안 떠 있으면 — Pod는 **에러도 없이 영원히 Pending**입니다 (아무도 그 Pod를 안 봅니다). 이벤트조차 없어서 헤매기 쉽습니다. Pending + 이벤트 없음 = schedulerName 오타/부재부터 의심.

## 2. 커스텀 스케줄러의 권한 부족

스케줄러는 의외로 많은 권한이 필요합니다(pods/binding 생성, nodes/PVC/PV 읽기, events 기록, lease...). 권한 한두 개가 빠지면 "어떤 Pod는 되고 어떤 Pod(PVC 달린 것)는 안 되는" 부분 고장이 납니다. `system:kube-scheduler` ClusterRole을 기반으로 시작하고 로그의 Forbidden을 추적하세요.

## 3. bin-packing을 켜고 PDB/분산을 안 챙김

MostAllocated로 비용을 아끼면 한 노드에 같은 서비스가 몰립니다 — 노드 1대 장애가 서비스 전멸로. bin-packing은 반드시 **topologySpread(모듈 12) + PDB(모듈 19)** 와 세트로. Karpenter consolidation도 같은 주의가 필요합니다.

## 4. 선점을 막는 PDB의 역설

PDB가 너무 빡빡하면(minAvailable=replicas) 선점 희생자를 찾지 못해 **긴급 Pod도 Pending**이 됩니다 — "preemption: not eligible due to a Pod Disruption Budget" 메시지. 가용성 보호와 긴급 배치 능력은 트레이드오프입니다.

## 5. 같은 Pod를 두 스케줄러가 보게 만드는 설정

멀티 프로파일/멀티 스케줄러에서 schedulerName이 겹치거나 한쪽이 와일드카드로 동작하면 — 두 스케줄러가 같은 Pod에 다른 노드를 binding 시도, 간헐 충돌과 미스터리 재배치. 스케줄러별 이름을 엄격히 분리하고, 커스텀 스케줄러의 watch 필터를 확인하세요.

## 실무 사고 사례

> 비용 절감 TF가 자체 bin-packing 스케줄러를 배치 워크로드에 도입 — 첫 달 노드 비용 30% 절감으로 성공처럼 보였습니다. 두 달 뒤 Spot 회수가 몰린 날, 빽빽하게 채워진 노드 하나가 사라질 때마다 **수십 개 Pod가 동시에 갈 곳을 잃었고**, 재스케줄 폭주 + 이미지 풀 폭주로 연쇄 지연. spreading이었다면 노드당 손실이 작아 흡수됐을 것. 결론은 롤백이 아니라 보완: 배치만 bin-packing, 서비스는 spreading 유지 + 노드당 동일 서비스 상한(topologySpread maxSkew). 교훈: **배치 성향은 비용·가용성·복구속도의 3변수 최적화입니다 — 한 변수만 보고 틀면 두 달 뒤에 청구서가 옵니다.**
