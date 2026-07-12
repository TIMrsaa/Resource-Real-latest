# 22 — 비용 최적화: 청구서를 Pod 단위로 해부하기

> AWS 청구서는 "EC2 $8,400"까지만 말해줍니다 — 어느 팀의 어느 서비스가 얼마인지는 침묵합니다. 이 모듈은 그 침묵을 깹니다: EKS 비용의 전체 해부(숨은 3대장 포함), 절감의 사다리(끄기→다이어트→압축→단가→아키텍처), 그리고 OpenCost로 **네임스페이스/팀 단위 계량기**를 다는 것까지. 34의 cost-center 라벨이 여기서 결실을 맺습니다.

## 학습 목표

1. EKS 비용 구조를 해부합니다 — 노드 밖의 숨은 3대장(데이터 전송·NAT·관측)까지
2. 고아 리소스(미부착 EBS, 유령 LB, 방치 스냅샷)를 CLI로 색출합니다
3. requests와 실사용의 갭을 측정합니다 — "예약이 곧 비용"의 실증
4. 절감 사다리 5단(끄기/right-sizing/bin-packing/단가/아키텍처)의 순서와 근거를 압니다
5. OpenCost로 ns/라벨 단위 비용 배분을 세우고 쇼백 표를 만듭니다

## 선행: eks 05(노드), 12(관측 비용), 17(consolidation·Spot), 19(Graviton), k8s 34(cost-center 라벨) · 환경: 공유 EKS
## 비용: OpenCost/Prometheus는 클러스터 내 무과금 — 아이러니하게도 이 모듈이 가장 쌉니다

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-cost-xray.md](./lab-01-cost-xray.md) — 고아 색출, requests 갭 측정, 정찰 보고서
3. [lab-02-opencost.md](./lab-02-opencost.md) — 계량기 설치, 배분 API, 쇼백 표
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
