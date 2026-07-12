# 학습 가이드 — 두 GitOps 도구, 하나의 원칙

## 12의 교훈이 GitOps에도

12에서 "CI 도구는 개념이 이식된다"를 배웠습니다. GitOps 도구도 마찬가지입니다 — ArgoCD와 Flux는 **같은 OpenGitOps 원칙**을 구현합니다:

```
선언적(Declarative) / 버전관리·불변(git) / 자동으로 당김(pulled automatically) / 지속 조정(continuously reconciled)
```

reconcile 루프, git이 진실, drift 교정, pull 모델 — 14에서 배운 것이 Flux에도 그대로입니다. 그래서 이 모듈은 Flux를 "처음부터"가 아니라 **ArgoCD와 대조**하며 배웁니다. 새 개념이 아니라 같은 개념의 다른 표현.

## 설계 철학의 차이

같은 원칙이지만 설계 결정이 다릅니다:

```
ArgoCD:  하나의 큰 애플리케이션 + 강력한 UI
  - Application CRD 하나가 sync/health/UI를 통합
  - 사람이 대시보드로 보는 GitOps
  - "애플리케이션 배포 플랫폼"

Flux:    작은 전문 컨트롤러들의 조합 (유닉스 철학)
  - source-controller(git/helm/oci 가져오기)
  - kustomize-controller(적용)
  - helm-controller(Helm)
  - image-controller(이미지 자동화)
  - notification-controller(알림)
  - "쿠버네티스에 GitOps를 이식하는 툴킷"
```

이 차이가 실무 선택을 가릅니다: UI 중심 팀은 ArgoCD, 조합·자동화 중심 팀은 Flux. eks 파트의 "관리형 vs 조합"(20의 메시 논의)과 같은 저울질입니다.

## Flux가 내장한 것: 이미지 자동화

14에서 GitOps의 경계 ②("이미지 태그를 누가 git에 업데이트하나")를 봤습니다. ArgoCD는 별도 컴포넌트(Image Updater)가 필요하지만, **Flux는 image-controller가 내장**입니다 — 레지스트리를 감시해 새 이미지를 발견하면 git을 자동 업데이트합니다. lab-02에서 이것을 실습하며, 04의 "다이제스트로 배포"가 자동화되는 것을 봅니다.

## 이 모듈의 목표

"어느 것이 우월한가"가 아닙니다(둘 다 CNCF Graduated, 둘 다 프로덕션급). 목표는 ① 두 도구를 대조해 GitOps 원칙의 이식성을 확정하고 ② 설계 철학으로 선택하는 능력을 갖추는 것. 그리고 14+15를 합쳐 **GitOps를 도구 독립적으로** 이해하게 되는 것.
