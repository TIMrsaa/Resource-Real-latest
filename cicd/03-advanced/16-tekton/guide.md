# 학습 가이드 — CI가 클러스터 리소스가 될 때

## 패러다임의 완성

이 파트의 큰 흐름:

```
03~13: CI가 SaaS/도구 (Actions, GitLab, Jenkins)
14~15: CD가 K8s 네이티브 (GitOps 컨트롤러)
16:    CI도 K8s 네이티브 (Tekton) ← 여기
```

Tekton은 "CI 파이프라인을 클러스터 리소스로" 만듭니다 — Task는 CRD, PipelineRun은 실행, 각 step은 Pod의 컨테이너. GitHub Actions가 GitHub에 매여 있고(SaaS), Jenkins가 controller에 상태를 갖는(13) 것과 달리, Tekton은 **쿠버네티스 그 자체가 CI 엔진**입니다.

이것이 왜 중요한가:

- **이식성**: 클러스터가 있으면 어디서든 같은 CI (온프레·멀티클라우드·에어갭)
- **통합**: CD(GitOps)와 같은 세계 — CRD, reconcile, kubectl로 관리
- **재사용**: Task가 클러스터 리소스라 팀·프로젝트 간 공유(Tekton Hub)

## 그러나 Tekton은 로우레벨입니다

Tekton의 정직한 특징: **로우레벨 빌딩 블록**입니다. GitHub Actions가 "워크플로를 쓰면 됨"이라면, Tekton은 "CI 시스템을 조립하는 부품"입니다 — Task·Pipeline·Trigger를 직접 조립해야 하고, UI·시크릿 관리·트리거를 스스로 구성합니다.

그래서 Tekton은 대개 **직접 쓰는 것이 아니라 그 위에 무언가를 얹습니다**: OpenShift Pipelines, Jenkins X, 또는 사내 플랫폼의 엔진으로. "플랫폼 팀이 개발자에게 CI를 제공하는" 시나리오의 하부구조입니다.

## 12의 이식성, 마지막 확인

12에서 "개념은 이식된다"를 배웠습니다. Tekton은 그 이식성의 또 다른 증거 — 그리고 매핑이 흥미롭습니다:

```
Task    = 재사용 가능한 잡 정의 (Actions의 composite action)
step    = Actions step (컨테이너)
Pipeline = 워크플로 (Task들의 조합)
TaskRun/PipelineRun = 실행 인스턴스
Workspace = 잡 간 볼륨 공유 (Actions artifacts의 볼륨판)
```

이 매핑으로 Tekton YAML을 읽으면 "또 다른 어휘"임이 보입니다.

## 판단이 핵심

이 모듈의 실무 목표는 "Tekton을 쓸 줄 아는 것"보다 **"언제 Tekton인가"를 판단하는 것**입니다. 대부분의 조직에는 GitHub Actions가 맞습니다(SaaS의 편의). Tekton이 정당한 것은 특정 맥락(멀티클라우드 이식성, 온프레/에어갭, CI 플랫폼 구축)입니다 — lab-02가 이 판단을 다룹니다.
