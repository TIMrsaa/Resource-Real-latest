# Part 3 — CI/CD 전체 생태계 ✅ (28개 모듈 완료)

> **목표**: "파이프라인을 돌릴 줄 아는" 수준이 아니라 러너의 동작 원리, GitOps 컨트롤러의 reconcile 루프, 공급망 보안 체계까지 이해하고, actions/runner나 argoproj에 기여하는 것.
> **범위**: GitHub Actions, AWS Code 시리즈, GitLab CI, Jenkins, Tekton, ArgoCD/Flux, 공급망 보안 — 전체 생태계
> **선행**: [k8s 파트](../k8s/README.md), [eks 파트](../eks/README.md)

---

## 진도 체크리스트

### 01-beginner — 초급 ✅ (작성 완료)
- [x] **01-cicd-concepts** — CI/Delivery/Deployment 구분, merge hell의 수학, 파이프라인 3원칙, DORA 4지표
- [x] **02-git-workflows** — "릴리스 모델이 브랜치 전략을 정한다", 세 모델 실행 비교, 브랜치 보호, 리뷰 시간 실측
- [x] **03-github-actions-basics** — 실행 모델 4층과 격리 경계, `pull_request_target` 인젝션, `ci` 게이트 구현
- [x] **04-docker-build-ci** — 레이어 캐시 규칙, 멀티스테이지/distroless, BuildKit 캐시·시크릿, 다이제스트 배포
- [x] **05-testing-in-ci** — 피라미드 경제학, Fake vs Mock, service container 격리, **flaky 격리 시스템**, diff 커버리지

### 02-intermediate — 중급 ✅ (작성 완료)
- [x] **06-gha-advanced** — reusable workflow/composite action, environments(승인·배포브랜치), 동적 매트릭스
- [x] **07-gha-oidc-aws** — OIDC 신뢰 흐름, `sub` 조건 설계, 04의 장기 키 부채 상환, 환경별 역할
- [x] **08-gha-self-hosted** — ARC on EKS, ephemeral 러너, 퍼블릭 저장소 금지, 러너 IAM 경계
- [x] **09-aws-codepipeline** — 오케스트레이션 철학, CodeStar Connection, 아티팩트 흐름, IAM 분리
- [x] **10-codebuild-deep** — buildspec 페이즈, 캐시 3종, VPC 빌드(NAT 대가), EKS 배포
- [x] **11-codedeploy-strategies** — 트래픽 전환, 자동 롤백(관찰이 게이트), expand-contract 마이그레이션
- [x] **12-gitlab-ci** — 개념 이식성 매핑, stage 1급 개념, 통합 철학, DAG
- [x] **13-jenkins** — Pipeline as Code, controller 상태성, 플러그인 양날, 마이그레이션(strangler fig)

### 03-advanced — 고급 ✅ (작성 완료)
- [x] **14-argocd-deep** — push→pull 역전, reconcile 루프, sync wave, ApplicationSet, selfHeal/prune
- [x] **15-flux-deep** — 컨트롤러 조합 철학(source/kustomize/helm), 이미지 자동화 파이프라인
- [x] **16-tekton** — K8s 네이티브 CI: Task/Pipeline이 CRD, Triggers, "CI를 CRD로 짓는" 트레이드오프
- [x] **17-progressive-delivery** — Argo Rollouts 카나리, AnalysisTemplate(관찰이 게이트), 11+14+15+eks13의 합류
- [x] **18-custom-actions-dev** — JS 액션 개발(툴킷·ncc 번들), dist 재현성 검증, 소비자→생산자→기여자
- [x] **19-buildkit-advanced** — LLB·솔버·캐시 익스포트(min/max), 멀티아치 3법, ko/buildpacks/kaniko 지형
- [x] **20-monorepo-ci** — affected 3단계(path filter→그래프→Bazel), 동적 매트릭스, `ci` 게이트 필수화

### 04-production — 실무 ✅ (작성 완료)
- [x] **21-supply-chain-security** — 공격 지도(xz·SolarWinds·tj-actions), SLSA, keyless 서명(OIDC 재등장), SBOM, admission 게이트
- [x] **22-secrets-management** — 없애기→줄이기→관리하기, Vault 동적 시크릿, GitOps 3해법(sealed/SOPS/ESO), CircleCI 2023
- [x] **23-pipeline-observability** — 메트릭 3계층, DORA 측정학, queue time(L=λW 재등장), critical path, flaky 운영
- [x] **24-enterprise-patterns** — 강제는 좁게·유인은 넓게(golden path), SoD·컴플라이언스 3요소, CAB의 반증, Policy as Code
- [x] **25-cicd-troubleshooting** — 3질문 분류기 + 진단 카드 10장, 캐시 오염·데드락·거짓 초록 재현, Game Day

### 05-contributor — 기여자 ✅ (작성 완료)
- [x] **26-actions-runner-contrib** — Listener/Worker 해부, _diag 진단, 생태계 4저장소의 문 고르기 (기업 주도 전략)
- [x] **27-argoproj-contrib** — argo-cd 3컴포넌트·gitops-engine 경계, start-local 루프, CNCF 오픈 거버넌스
- [x] **28-tekton-contrib** — ko 개발 루프(19의 합류), entrypoint 트릭, TEP·catalog, CDF + k8s식 프로세스

### reference ✅
- [x] [cheatsheet-gha.md](./reference/cheatsheet-gha.md) — 안전 기본값·게이트 패턴·디버깅
- [x] [cheatsheet-argocd.md](./reference/cheatsheet-argocd.md) — refresh vs sync 중심 명령 지도
- [x] [glossary.md](./reference/glossary.md) — 커리큘럼 맥락의 용어 정의 (모듈 참조 포함)
- [x] [links.md](./reference/links.md) — 1차 소스·사고 사례 원문

---

## 이 파트의 서사 — 다섯 개의 관통선

1. **피드백 루프의 경제학** (01→05→20→23): merge hell의 수학에서 시작해, 테스트 피라미드, affected 빌드, critical path까지 — "작고 빠른 루프"가 모든 설계의 원기(原器)입니다.
2. **신뢰 경계와 공급망** (03→07→18→19→21→22): 포크 PR의 시크릿 미제공에서 시작한 경계 감각이 OIDC(장기 키 제거), dist 재현성, provenance, keyless 서명, 시크릿 제거로 자라 하나의 체계가 됩니다.
3. **push에서 pull로** (09~13→14~15→17): 오케스트레이터들(Code 시리즈·GitLab·Jenkins)을 지나 GitOps의 역전(Git이 진실)에 도달하고, Progressive Delivery에서 "관찰이 게이트"로 완성됩니다.
4. **규율의 게이트화** (02→24→25): 브랜치 보호에서 시작한 강제가 Policy as Code(파이프라인 정의 자체를 검사)와 "포스트모템은 게이트가 되어야 끝난다"로 진화합니다.
5. **소비자→생산자→기여자** (03→18→26~28): 남의 액션을 쓰던 사람이 액션을 만들고, 마침내 러너·ArgoCD·Tekton의 소스를 고칩니다 — 거버넌스 3유형(기업/CNCF/CDF)별 전략과 함께.

## 의존 지도 (무엇이 무엇을 먹여 살리나)

```
01 개념 ─┬─ 02 브랜치 ── 24 거버넌스 ── 25 트러블슈팅(총결산)
         ├─ 03 GHA 기초 ─┬─ 06 고급 ── 07 OIDC ── 08 러너 ─── 26 runner 기여
         │               └─ 18 액션 개발 ──────┐
         ├─ 04 빌드 ── 19 BuildKit ── 21 공급망 ┴─ 22 시크릿
         ├─ 05 테스트 ── 20 모노레포 ── 23 관측
         └─ 09~13 오케스트레이터들 ── 14 ArgoCD ─┬─ 15 Flux
                                                ├─ 16 Tekton ── 28 tekton 기여
                                                └─ 17 Progressive ── 27 argoproj 기여
외부 합류: eks 13(Little's Law → 23), eks 14(ALB → 17), eks 17(Karpenter → 08·19), k8s 34(admission → 21)
```

> **다음 파트**: [Part 4 — CNCF 생태계](../cncf/README.md) — argoproj(27)가 살고 있는 그 재단의 전체 지형으로.
