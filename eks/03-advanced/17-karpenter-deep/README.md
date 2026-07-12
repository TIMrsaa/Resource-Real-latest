# 17 — Karpenter 심층: 노드를 계산으로 만드는 컨트롤러

> 15의 HPA가 Pod를 늘리면, 노드는 누가 늘리나요? 구세대 답(Cluster Autoscaler)은 "미리 정한 크기의 노드그룹을 한 대 더"였습니다. Karpenter의 답은 다릅니다 — **Pending Pod들을 읽고, 수백 개 인스턴스 타입 중 최적 조합을 계산해, ASG 없이 EC2를 직접 부릅니다.** 이 모듈은 그 계산(provisioning), 되감기(consolidation), 그리고 규칙서(NodePool) 설계를 해부합니다. 04의 Auto Mode가 숨겨놓은 그 엔진의 원형입니다.

## 학습 목표

1. CA와 Karpenter의 구조 차이(ASG 경유 vs EC2 직접, group vs groupless)를 설명합니다
2. provisioning 파이프라인(pending 감지 → 스케줄링 시뮬레이션 → 타입 선정 → NodeClaim)을 추적합니다
3. NodePool/EC2NodeClass를 설계합니다 — requirements의 폭이 가격과 속도를 정하는 원리
4. consolidation(delete/replace)을 관찰하고 disruption budget·do-not-disrupt로 통제합니다
5. Spot 혼합과 중단(interruption) 처리, 그리고 16(IP)·34(테넌트 격리)와의 접점을 압니다

## 선행: eks 04(Auto Mode), 05(노드그룹/ASG), 13(측정), 15(HPA), 16(IP 예산) · 환경: 공유 EKS
## ⚠️ 비용: Karpenter가 만드는 실험 노드(소형 spot/on-demand) — cleanup이 NodePool 삭제로 회수까지 확인

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-install-provision.md](./lab-01-install-provision.md) — 설치, 첫 NodePool, "왜 이 타입?" 해부
3. [lab-02-consolidation-spot.md](./lab-02-consolidation-spot.md) — 되감기 관찰과 통제, Spot
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh` (★ 노드 회수 확인)

소요: 이론 2h + 실습 2.5h
