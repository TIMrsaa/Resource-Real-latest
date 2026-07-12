# 17 — Flux 심층: 컨트롤러 조합이라는 철학

> cicd 15에서 Flux를 사용자로 배웠다면, 이 모듈은 **왜 Flux가 그렇게 생겼는가**를 팝니다. ArgoCD(16)가 "제품"이라면 Flux는 "**툴킷**"입니다 — 하나의 큰 컨트롤러 대신 네 개의 작은 컨트롤러(source·kustomize·helm·notification)를 조합하고, 각각이 독립된 CRD와 재사용 가능한 라이브러리(GitOps Toolkit)로 존재합니다. 이 설계가 무엇을 얻고 무엇을 잃는지, 그리고 왜 다른 프로젝트들(Flagger, 여러 플랫폼)이 Flux 위에 지어지는지가 이 모듈의 내용입니다.

## 학습 목표

1. GitOps Toolkit의 컨트롤러 4종과 CRD 조합 방식을 이해합니다 (Source가 다른 컨트롤러의 입력)
2. Flux의 조정(reconcile) 모델 — 소스 갱신과 적용의 분리 — 을 ArgoCD와 대비합니다
3. HelmRelease가 Helm의 릴리스 상태 기계를 어떻게 살리는지(15와 연결) 확인합니다
4. 이미지 자동화(image-reflector/automation)로 "레지스트리 → Git 커밋" 루프를 만듭니다
5. 멀티테넌시(테넌트별 SA 임퍼소네이션)와 Flux vs ArgoCD 선택 기준을 세웁니다

## 선행: cicd 14·15(GitOps), 15(Helm 릴리스), 16(ArgoCD) · 도구: kind, kubectl, flux CLI, gh
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-toolkit-composition.md](./lab-01-toolkit-composition.md) — 컨트롤러 조합, Source의 재사용
3. [lab-02-image-automation-and-tenancy.md](./lab-02-image-automation-and-tenancy.md) — 이미지 자동화, 멀티테넌시
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
