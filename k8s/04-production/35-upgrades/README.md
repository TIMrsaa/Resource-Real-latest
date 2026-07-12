# 35 — 업그레이드: 달리는 클러스터의 버전 올리기

> Kubernetes는 1년에 세 번 마이너 버전을 내고, 각 버전은 약 14개월 뒤 지원이 끝납니다. 업그레이드는 "언젠가"가 아니라 **분기마다 돌아오는 정기 운항**입니다 — 이 모듈은 그것을 사고 없이 반복하는 절차(runbook)를 만듭니다.

## 학습 목표

1. 버전 skew 정책이 업그레이드 **순서**를 어떻게 강제하는지 설명합니다
2. preflight(폐기 API 탐지 · PDB 점검 · 애드온 호환 · 백업)를 게이트로 세웁니다
3. Pluto(정적)와 EKS cluster insights(동적)로 폐기 API를 사전 탐지합니다
4. cordon → drain → 교체의 무중단 노드 교체를 직접 수행하고, PDB 데드락을 재현·해소합니다
5. in-place / Blue-Green 노드그룹 / Blue-Green 클러스터 전략의 트레이드오프를 압니다

## 선행: 모듈 12(taint·cordon), 19(PDB), 24(SSA — 애드온과 연결), reference/api-deprecations · 환경: 공유 EKS

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-preflight.md](./lab-01-preflight.md) — 폐기 API 탐지, insights, PDB 점검
3. [lab-02-node-upgrade.md](./lab-02-node-upgrade.md) — drain 무중단 교체 + 데드락 재현
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
