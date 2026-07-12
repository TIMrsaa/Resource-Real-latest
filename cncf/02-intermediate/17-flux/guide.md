# 학습 가이드 — 제품과 툴킷, 두 철학

## 같은 문제, 다른 설계 철학

ArgoCD와 Flux는 GitOps라는 같은 문제를 풉니다. 그런데 코드를 열면 완전히 다른 세계입니다:

```
ArgoCD: Application CRD 하나 + 큰 컨트롤러 하나 + 훌륭한 UI
        → "설치하면 GitOps 제품이 생긴다"

Flux:   GitRepository / OCIRepository / Kustomization / HelmRelease / ImagePolicy ...
        각각 독립 CRD + 각각 독립 컨트롤러 + UI 없음(CLI와 CR로)
        → "GitOps를 지을 부품을 준다"
```

이 차이가 실무의 모든 것을 결정합니다. Flux에서는 "GitRepository 하나를 여러 Kustomization이 참조"하고, "HelmRelease가 GitRepository든 HelmRepository든 OCIRepository든 소스로 삼는다" — **소스와 적용이 분리**되어 있어 조합이 자유롭습니다. 대신 UI가 없고, 개념을 여럿 알아야 하며, "이 앱의 상태"를 한 화면에서 보려면 도구를 붙여야 합니다.

## 왜 다른 프로젝트가 Flux 위에 지어지나

Flagger(Progressive Delivery), 여러 상용 플랫폼, 그리고 일부 내부 플랫폼이 Flux를 **라이브러리로** 씁니다 — GitOps Toolkit의 컨트롤러들이 독립적이고 API가 명확하기 때문입니다. 08의 "오퍼레이터는 사다리를 관통하는 확장 문법"이 여기서 극대화됩니다: Flux는 자기 자신도 CRD의 조합이고, 남이 그 조합에 부품을 추가할 수 있습니다.

ArgoCD가 gitops-engine을 별도 저장소로 뽑았던 것(cicd 27)과 대비하면 흥미롭습니다 — 둘 다 "재사용 가능한 코어"를 지향했지만, Flux는 처음부터 그렇게 설계됐고 ArgoCD는 나중에 분리했습니다.

## Helm의 두 진실 문제, Flux의 답

15에서 본 긴장 — "릴리스 Secret이 진실"(Helm) vs "Git이 진실"(GitOps) — 에 Flux는 ArgoCD와 다른 답을 냅니다: **HelmRelease CR을 Git에 두고, helm-controller가 실제 Helm 릴리스를 만듭니다.** 즉 Helm의 상태 기계(history·rollback·훅)를 살리면서, "무엇을 설치할지"의 선언만 Git에 둡니다.

ArgoCD 방식(helm template으로 렌더링만)과 비교하면 트레이드오프가 선명합니다: Flux는 helm rollback을 쓸 수 있고 차트의 훅이 온전히 동작하지만, "클러스터에 실제로 무엇이 갔는가"의 diff는 Helm 릴리스를 거쳐야 보입니다.

## 이 모듈의 끝 — 선택의 근거

48(비교 가이드)에서 본격적으로 다루지만, 여기서 이미 판단 재료가 모입니다: 팀이 UI를 원하는가 CR을 원하는가, 소스와 적용의 분리가 필요한가, Helm 릴리스 상태를 살려야 하는가, 멀티테넌시를 네임스페이스 경계로 세울 것인가. **"어느 것이 더 좋은가"가 아니라 "우리 조직의 어느 성질과 맞는가"**가 옳은 질문입니다.
