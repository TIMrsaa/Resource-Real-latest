# 27 — argoproj에 기여하기: CNCF Graduated 프로젝트의 안쪽

> 14에서 ArgoCD의 reconcile 루프를 사용자로 해부했고, 17에서 Rollouts의 카나리를 운영했습니다 — 이제 그 컨트롤러들의 개발자로 들어갑니다. argoproj는 26의 actions/runner와 정반대의 거버넌스입니다: **CNCF Graduated의 오픈 거버넌스** — 여러 회사의 유지보수자, 공개 제안(proposal) 절차, 기여자 미팅. 코드 구조에도 eks 28(Karpenter 코어/프로바이더)과 같은 2저장소 통찰이 있습니다: sync 엔진은 argo-cd가 아니라 **gitops-engine**이라는 별도 저장소입니다. 어디를 고칠지 판정하는 것이 첫 관문입니다.

## 학습 목표

1. argoproj 4형제(argo-cd/rollouts/workflows/events)와 gitops-engine의 경계를 읽고 — 내 변경이 어느 저장소인지 판정합니다
2. argo-cd 코드 지도를 그립니다: application-controller(14의 reconcile), repo-server(Git→매니페스트), server(API/UI)
3. 소스에서 빌드해 kind 클러스터를 상대로 로컬 실행하고, 14에서 배운 reconcile을 로그·코드로 추적합니다
4. 테스트 문화(단위·e2e)와 기여 경로(good-first-issue → 코드/UI/docs/triage)를 밟습니다
5. 오픈 거버넌스의 문법 — proposal, 기여자 미팅, 멀티 벤더 유지보수자 — 을 26의 기업 주도와 대비해 이해합니다

## 선행: 14(ArgoCD 내부 — 필수), 17(Rollouts), k8s 41~45(기여 문법), Go 기초 · 도구: Go 1.23+, kind, kubectl, git, gh
## 비용: 없음 (로컬 kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-build-and-reconcile.md](./lab-01-build-and-reconcile.md) — 빌드, 로컬 실행, reconcile 추적
3. [lab-02-test-and-contribute.md](./lab-02-test-and-contribute.md) — 테스트, 이슈 탐색, 기여 경로
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h
