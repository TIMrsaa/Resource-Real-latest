# 23 — 멀티클러스터: 하나로 안 되는 날의 설계

> 34에서 "ns로 안 되는 요구"의 끝은 클러스터 분리였습니다. 그 문을 열면 새 세계가 시작됩니다 — 클러스터가 2개, 10개, 리전이 2개가 되는 순간, 배포·버전·트래픽·데이터가 전부 **곱하기**가 됩니다. 이 모듈은 그 곱셈을 관리하는 패턴들입니다: fleet 표준화(GitOps), 글로벌 트래픽(Route53/GA), 그리고 페더레이션의 실패사가 남긴 교훈.

## 학습 목표

1. 멀티클러스터로 가는 신호 5종과 "가지 말아야 할 이유"를 판별합니다
2. 아키텍처 스펙트럼(독립+표준화 / active-passive / active-active / cell)을 그립니다
3. kubefed의 실패에서 현대의 답(GitOps fleet)이 나온 맥락을 이해합니다
4. vCluster로 가상 클러스터 2개를 세워 **fleet 표준화와 drift 탐지**를 실습합니다
5. 글로벌 트래픽 계층(Route53 정책/Global Accelerator)과 페일오버를 모형으로 실증합니다 — 그리고 "진짜 문제는 데이터"임을 압니다

## 선행: k8s 34(vCluster·격리 스펙트럼), 36(Velero — 클러스터 간 이사), 39(GitOps), eks 21(fleet 업그레이드) · 환경: 공유 EKS
## 비용: vCluster는 호스트 클러스터 안의 Pod — 추가 클러스터 요금 없음 (실물 멀티리전은 이론으로)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-fleet-vcluster.md](./lab-01-fleet-vcluster.md) — 가상 클러스터 2개, 표준화, drift
3. [lab-02-failover-model.md](./lab-02-failover-model.md) — 페일오버 모형과 RTO 실측
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
