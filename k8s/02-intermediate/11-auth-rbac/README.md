# 11 — 인증, 인가, RBAC

> "누구냐(인증) → 뭘 해도 되냐(인가)"를 해부합니다. Secret 보안(모듈 07)의 본체였던 RBAC를 설계하고, EKS의 IAM 연동까지.

## 학습 목표

1. API 요청 파이프라인에서 인증/인가/admission의 위치를 압니다
2. K8s에 "User 객체가 없다"는 사실과 인증 방식들(인증서/토큰/OIDC/IAM)을 이해합니다
3. Role/ClusterRole/RoleBinding/ClusterRoleBinding 4종 조합을 설계합니다
4. ServiceAccount로 Pod에 권한을 부여하고 최소 권한 원칙을 적용합니다
5. `kubectl auth can-i`와 EKS access entries로 권한을 검증/관리합니다

## 선행: 모듈 02, 07, 09 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-rbac-basics.md](./lab-01-rbac-basics.md) — Role/Binding 만들고 권한 경계 확인
3. [lab-02-serviceaccount-eks.md](./lab-02-serviceaccount-eks.md) — Pod 권한 + EKS access entries
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
