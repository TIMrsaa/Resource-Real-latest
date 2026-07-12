# 17 — Progressive Delivery: 카나리를 자동화합니다

> 11에서 카나리를 배웠지만 "관찰 후 확대"가 사람의 판단이었습니다. 14~15에서 GitOps로 배포가 선언이 됐습니다. 이 모듈은 둘을 합칩니다 — **Argo Rollouts/Flagger**가 메트릭을 자동 분석하고, 좋으면 확대, 나쁘면 자동 롤백합니다. 11에서 "지표 없는 카나리는 느린 배포"라 했는데, 여기서 그 지표(eks 13·15)가 배포의 자동 게이트가 됩니다. CI/CD 파이프라인의 안전이 완성되는 지점.

## 학습 목표

1. Progressive Delivery가 11(카나리)+14(GitOps)+eks 13/15(SLI)의 합류임을 이해합니다
2. Argo Rollouts의 구조(Rollout CRD, AnalysisTemplate, 트래픽 관리)를 압니다
3. 메트릭 기반 자동 분석·자동 롤백을 구현합니다 — 사람 판단을 지표로 대체
4. 트래픽 관리(eks 14 ALB / 20 메시)와 Rollouts의 결합을 압니다
5. Flagger와 비교하고, 분석 지표 설계의 함정을 압니다

## 선행: 11(배포 전략·롤백), 14(GitOps·ArgoCD), eks 13(SLI/측정)·14(트래픽)·15(메트릭 HPA) · 환경: 공유 EKS
## ⚠️ 비용: Rollouts는 클러스터 내(무과금), 배포 워크로드

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-rollout-canary.md](./lab-01-rollout-canary.md) — Rollout 카나리, 수동 승격
3. [lab-02-analysis-autorollback.md](./lab-02-analysis-autorollback.md) — 메트릭 자동 분석·롤백
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
