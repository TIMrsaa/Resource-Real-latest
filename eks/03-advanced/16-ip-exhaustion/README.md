# 16 — IP 고갈: 진단, 소진 방정식, 그리고 구조적 탈출구

> EKS의 원죄: **Pod 하나 = VPC IP 하나** (07의 그 설계). 편리함의 대가로, 클러스터가 크면 서브넷이 마릅니다 — 그리고 고갈은 "Pod가 안 뜨는" 순간이 아니라 설계 때 이미 결정돼 있습니다. 이 모듈은 남은 IP를 계산하는 법, 마르기 전에 아는 법, 그리고 세 단계 탈출구(prefix delegation → secondary CIDR/custom networking → IPv6)를 다룹니다.

## 학습 목표

1. IP 소진 방정식(서브넷 크기 × AZ, warm pool, Pod 밀도)을 세우고 **"몇 Pod 남았나"를 계산**합니다
2. 고갈의 증상(ContainerCreating, ipamd 로그)과 진단 루틴을 갖춥니다
3. warm 설정(WARM_IP_TARGET 등)의 트레이드오프를 압니다 — 과예약 vs 기동 지연
4. secondary CIDR + custom networking(ENIConfig)으로 Pod를 **다른 대역으로 이주**시킵니다 (실습)
5. IPv6 클러스터의 약속과 제약(신규 생성만, egress 경로)을 설계 수준에서 판단합니다

## 선행: eks 07(VPC CNI — 이 모듈의 기반), 05(노드그룹), 12(알람) · 환경: 공유 EKS
## ⚠️ lab-02는 클러스터 전역 설정(aws-node env)을 만집니다 — 원복 절차 엄수, 소규모 노드그룹 비용 소량

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-diagnose-budget.md](./lab-01-diagnose-budget.md) — 실측, 소진 방정식, 잔여 계산기
3. [lab-02-custom-networking.md](./lab-02-custom-networking.md) — secondary CIDR로 Pod 이주
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh` (★ 노드그룹/CIDR 원복)

소요: 이론 1.5h + 실습 2.5h
