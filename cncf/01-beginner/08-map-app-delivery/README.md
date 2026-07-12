# 08 — 지도: 앱 정의와 배포 — 매니페스트에서 플랫폼까지

> cicd 14~17에서 ArgoCD·Flux·Progressive Delivery를 사용자로 깊게 배웠습니다 — 이 지도는 그들이 사는 동네 전체입니다. 축은 "**애플리케이션이 클러스터에 도달하기까지 거치는 추상의 사다리**"다: 매니페스트를 어떻게 쓰고(Helm·Kustomize), 어떻게 배달하고(ArgoCD·Flux), 어떻게 점진 전환하며(Argo Rollouts·Flagger), 그 위에 어떤 상위 추상을 얹는가(Operator·Crossplane·Backstage·Knative·Dapr). CNCF에서 프로젝트 밀도가 가장 높은 칸이고, 그래서 사다리를 모르면 로고 늪이 됩니다.

## 학습 목표

1. 앱 배포의 추상 사다리 5단(매니페스트 → 패키징 → 배달 → 점진 전환 → 상위 추상)을 그립니다
2. Helm과 Kustomize의 설계 철학(템플릿 vs 오버레이)과 공존 방식을 압니다
3. 오퍼레이터 패턴이 이 사다리의 어디에 있고, Operator SDK/Framework가 무엇을 자동화하는지 압니다
4. Crossplane·Backstage·Knative·Dapr가 각각 "무엇 위의 추상"인지 정확히 구분합니다
5. kind에서 Helm 렌더링과 Kustomize 오버레이를 비교하고, ArgoCD가 둘을 어떻게 소비하는지 확인합니다

## 선행: 01(범례), k8s(매니페스트·오퍼레이터), cicd 14~17(GitOps·Progressive) · 도구: kind, kubectl, helm, kustomize
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 지도 본체
2. [lab-01-category-census.md](./lab-01-category-census.md) — 전수 목록·사다리 배치
3. [lab-02-helm-vs-kustomize.md](./lab-02-helm-vs-kustomize.md) — 두 철학의 실물 비교
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
