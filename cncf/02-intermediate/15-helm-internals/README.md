# 15 — Helm 심층: 템플릿 엔진, 릴리스 상태, 그리고 v4

> 08의 사다리에서 2단(패키징)의 주인. "차트를 설치하는 도구"로만 알기엔 아까운 프로젝트입니다 — Helm은 **K8s에 없는 개념 하나를 발명했습니다: 릴리스(Release)**. 클러스터에는 Deployment·Service만 있고 "이 앱을 설치했다"는 상태는 없는데, Helm은 그것을 Secret에 저장해 업그레이드·롤백·삭제를 가능하게 합니다. 이 모듈은 세 축을 팝니다: 템플릿 엔진의 실체(YAML을 문자열로 다루는 대가), 릴리스 상태 기계(그리고 그것이 GitOps와 충돌하는 이유), Helm v3→v4 전환.

## 학습 목표

1. 차트의 구조와 렌더링 파이프라인(values 병합 → 템플릿 → 매니페스트 → 후처리)을 압니다
2. 릴리스 상태가 어디에 어떻게 저장되는지 실물로 확인하고, 3-way 병합의 동작을 이해합니다
3. 템플릿 엔진의 함정(들여쓰기·타입·`nindent`·`toYaml`)과 방어(`--dry-run`, `helm lint`, 스키마)를 압니다
4. Helm 훅과 sync wave(cicd 14)의 대응, 그리고 훅의 위험을 압니다
5. Helm v4의 변화와 GitOps에서 Helm을 쓰는 두 방식(CD 렌더 vs CI 렌더)을 판단합니다

## 선행: 08(사다리), k8s(매니페스트), cicd 14(GitOps) · 도구: kind, kubectl, helm(v4)
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-render-and-release.md](./lab-01-render-and-release.md) — 렌더링 해부, 릴리스 Secret, 3-way 병합
3. [lab-02-hooks-and-gitops.md](./lab-02-hooks-and-gitops.md) — 훅·테스트, GitOps와의 충돌 지점
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
