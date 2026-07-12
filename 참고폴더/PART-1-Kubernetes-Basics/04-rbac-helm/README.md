# 04. RBAC & Helm — ServiceAccount, Role, Helm 차트

## 학습 목표

- **RBAC**: ServiceAccount, Role, RoleBinding 으로 K8s API 접근 권한 부여
- **Helm**: 매니페스트 묶음을 패키지로 관리, 환경별 values 분리
- **미니 프로젝트**: `order-service` 를 Helm 차트로 만들어 EKS에 배포

## 선행 지식

- 모듈 01~03 완료
- Helm 설치되어 있음 (`helm version`)

## 진행 순서

1. [theory.md](./theory.md) — 이론 (15분)
2. [lab-01-rbac.md](./lab-01-rbac.md) — 제한된 SA로 API 호출 (25분)
3. [lab-02-helm-chart.md](./lab-02-helm-chart.md) — order-service Helm 차트 작성 (40분)
4. [mini-project.md](./mini-project.md) — Part 1 미니 프로젝트 (60분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)
7. `bash cleanup.sh`

## 소요 시간

총 **약 2.5 ~ 3시간** (미니 프로젝트 포함).

## 다음 단계

→ Part 2: [PART-2-EKS-Practice](../../PART-2-EKS-Practice/)
