# 09 — Namespace, Label, Annotation: 정리와 연결의 문법

> 지금까지 암묵적으로 써온 라벨과 default 네임스페이스를 정식으로 정리합니다. K8s에서 "조직화"의 전부.

## 학습 목표

1. Namespace의 격리 범위(이름/권한/쿼터)와 격리 안 되는 것(네트워크!)을 구분합니다
2. Label/Selector 문법(등호/집합 연산)을 자유롭게 씁니다
3. Label vs Annotation의 용도 차이를 압니다
4. 표준 라벨 세트(app.kubernetes.io/*)와 ResourceQuota/LimitRange를 실습합니다

## 선행: 모듈 04, 05 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-namespace-quota.md](./lab-01-namespace-quota.md) — 네임스페이스 생성, 격리 확인, 쿼터 체험
3. [lab-02-labels-selectors.md](./lab-02-labels-selectors.md) — 셀렉터 문법 훈련
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 45m + 실습 1h
