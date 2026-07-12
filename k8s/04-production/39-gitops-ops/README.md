# 39 — GitOps 운영: ArgoCD 기본

> "kubectl apply를 사람이 친다"에서 "Git이 진실이고 컨트롤러가 맞춘다"로 — 운영 패러다임의 전환. ArgoCD를 직접 설치해 동기화/드리프트 치유/롤백을 체험합니다. (파이프라인 전체 그림은 cicd 파트에서 — 여기선 K8s 쪽 절반)

## 학습 목표

1. GitOps 4원칙과 "push 배포 vs pull 배포"의 차이를 압니다
2. ArgoCD를 설치하고 Git 리포의 매니페스트를 동기화합니다
3. 드리프트(수동 변경)를 감지/자동 치유(selfHeal)하는 것을 봅니다
4. prune, sync wave, app-of-apps 등 운영 패턴의 개념을 잡습니다
5. "롤백 = git revert"의 의미를 체험합니다

## 선행: 모듈 17/18(Helm/Kustomize — ArgoCD가 렌더링에 사용), 10(선언형 철학) · 환경: 공유 EKS

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-argocd-install.md](./lab-01-argocd-install.md) — 설치와 첫 동기화
3. [lab-02-drift-selfheal.md](./lab-02-drift-selfheal.md) — 드리프트, 치유, prune, 롤백
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
