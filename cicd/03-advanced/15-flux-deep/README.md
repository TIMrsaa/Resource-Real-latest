# 15 — Flux 심층: 같은 원칙, 다른 설계

> 14에서 ArgoCD로 GitOps를 배웠습니다. Flux는 같은 원칙(pull·git이 진실·reconcile)의 다른 구현입니다 — 그런데 설계 철학이 다릅니다: ArgoCD가 "하나의 큰 컨트롤러 + UI"라면, Flux는 "작은 컨트롤러들의 조합(source/kustomize/helm/image)". 12에서 배운 이식성이 GitOps 영역에서도 성립함을 확인하고, 두 도구의 설계 결정이 갈리는 지점 — 특히 **이미지 자동화**(14의 경계 문제를 Flux는 내장) — 을 봅니다.

## 학습 목표

1. Flux의 컨트롤러 조합(source/kustomize/helm/image/notification)을 ArgoCD와 비교합니다
2. GitRepository·Kustomization·HelmRelease의 관계를 이해합니다
3. Flux의 이미지 자동화(image-reflector + image-automation)로 14의 경계 ②를 해결합니다
4. "ArgoCD vs Flux" 선택 기준을 설계 철학으로 세웁니다
5. GitOps 도구 독립적 원칙(OpenGitOps)을 확인합니다

## 선행: 14(ArgoCD·GitOps 원리), 12(이식성), 04(다이제스트) · 환경: 공유 EKS
## ⚠️ 비용: Flux는 클러스터 내(무과금)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-flux-controllers.md](./lab-01-flux-controllers.md) — 컨트롤러 조합, ArgoCD와 나란히
3. [lab-02-image-automation.md](./lab-02-image-automation.md) — 이미지 자동화, 선택 기준
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
