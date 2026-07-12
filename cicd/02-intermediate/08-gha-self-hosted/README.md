# 08 — Self-hosted 러너: ARC로 EKS 위에서 CI를 돌리입니다

> 03에서 "러너는 매번 새 VM이라 재현성이 보장된다"고 했습니다. 그런데 VPC 안의 DB에 접근해야 하는 통합 테스트는? 8vCPU가 필요한 빌드는? 분당 과금이 부담스러운 대규모 매트릭스는? 답이 self-hosted 러너입니다 — 그리고 그 순간 **재현성과 격리는 우리 책임**이 됩니다. 이 모듈은 ARC(Actions Runner Controller)로 EKS 위에 러너를 세우고, 그 자유가 데려오는 위험(persistent 러너 오염, 퍼블릭 저장소의 치명적 함정)을 다룹니다.

## 학습 목표

1. self-hosted가 정당한 네 가지 이유와, 그것이 포기하는 것을 압니다
2. ARC 구조(컨트롤러 + AutoscalingRunnerSet + ephemeral 러너 Pod)를 이해합니다
3. EKS에 ARC를 설치하고 워크플로를 그 위에서 실행합니다 — Karpenter(eks 17)와의 결합
4. **ephemeral 러너**가 왜 협상 불가능한지 압니다 — 오염된 러너의 공격 경로
5. 러너에서 OIDC(07)를 쓰고, 러너 자체의 IAM 경계를 설계합니다

## 선행: 03(러너 모델), 07(OIDC), k8s 파트 중급, eks 09(Pod Identity)·17(Karpenter) · 환경: 공유 EKS
## ⚠️ 비용: 러너 Pod가 노드를 요구합니다 — Karpenter가 노드를 만들 수 있음. cleanup 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-arc-on-eks.md](./lab-01-arc-on-eks.md) — ARC 설치, 첫 잡, 스케일 관찰
3. [lab-02-isolation-and-iam.md](./lab-02-isolation-and-iam.md) — 오염 실험, ephemeral 검증, 러너 IAM
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
