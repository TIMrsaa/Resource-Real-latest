# 09 — IRSA와 Pod Identity: Pod에게 AWS 권한 주기

> 모듈 08에서 "컨트롤러에 권한을 붙였던" 그 마법의 해부. Pod가 AWS API를 부르는 두 가지 공식 경로 — IRSA(OIDC 연합)와 Pod Identity(전용 에이전트) — 의 내부 동작을 토큰 레벨까지 파고, 마이그레이션 기준을 세웁니다.

## 학습 목표

1. "노드 역할을 다 같이 쓰면 안 되는 이유"(최소 권한)를 명확히 합니다
2. IRSA의 전체 경로(SA 토큰 → OIDC 신뢰 → STS AssumeRoleWithWebIdentity)를 해부합니다
3. Pod Identity의 경로(에이전트 → eks-auth API)와 IRSA 대비 단순화 지점을 압니다
4. SDK 자격증명 체인이 둘을 "자동으로" 집어가는 원리를 봅니다
5. 신규/기존 환경의 선택과 마이그레이션 기준을 세웁니다

## 선행: k8s 11(SA/RBAC — 특히 SA 토큰), eks 02(OIDC issuer 확인) · 환경: 공유 EKS

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-irsa-anatomy.md](./lab-01-irsa-anatomy.md) — IRSA를 손으로: OIDC→역할→토큰 해부
3. [lab-02-pod-identity.md](./lab-02-pod-identity.md) — Pod Identity 경로와 비교/마이그레이션
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
