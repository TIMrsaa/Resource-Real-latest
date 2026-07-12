# 링크 모음 — 1차 소스 우선

> 블로그보다 공식 문서·소스·연구를 먼저. 괄호는 관련 모듈.

## 개념·연구

- DORA 연구 (지표 정의·역량 모델): https://dora.dev (01·23·24)
- Accelerate (도서 — DORA의 원전) — 승인 절차 연구 포함 (24)
- Trunk-Based Development: https://trunkbaseddevelopment.com (02)
- Google Testing Blog (flaky·테스트 규모): https://testing.googleblog.com (05·23)

## GitHub Actions

- 공식 문서: https://docs.github.com/actions (03~08)
- 보안 강화 가이드: https://docs.github.com/actions/security-for-github-actions (03·21·22)
- OIDC 심층: https://docs.github.com/actions/deployment/security-hardening-your-deployments (07)
- actions/runner (소스): https://github.com/actions/runner — docs/adrs 포함 (26)
- actions/toolkit: https://github.com/actions/toolkit (18·26)
- runner-images: https://github.com/actions/runner-images (26)
- ARC: https://github.com/actions/actions-runner-controller (08·26)
- GitHub Status: https://www.githubstatus.com (25 — 3질문의 "플랫폼" 확인)

## AWS Code 시리즈 (09~11)

- CodePipeline: https://docs.aws.amazon.com/codepipeline/
- CodeBuild (buildspec): https://docs.aws.amazon.com/codebuild/
- CodeDeploy: https://docs.aws.amazon.com/codedeploy/
- ※ CodeCommit은 신규 가입 중단 — 소스는 GitHub + CodeStar Connection (09)

## 빌드 (04·19)

- Docker 공식 빌드 문서: https://docs.docker.com/build/ — drivers, multi-platform, cache
- BuildKit 소스: https://github.com/moby/buildkit — LLB·frontend 문서
- ko: https://ko.build / buildpacks: https://buildpacks.io
- Docker Hub rate limit: https://docs.docker.com/docker-hub/usage/ (25 카드 8)

## GitOps·배포 (12~17)

- ArgoCD: https://argo-cd.readthedocs.io — operator-manual/developer-guide (14·27)
- Flux: https://fluxcd.io/flux/ (15)
- Argo Rollouts: https://argo-rollouts.readthedocs.io (17)
- Flagger: https://flagger.app (17)
- Tekton: https://tekton.dev/docs/ (16·28)
- GitLab CI: https://docs.gitlab.com/ee/ci/ (12)
- Jenkins: https://www.jenkins.io/doc/ (13)

## 공급망·시크릿 (21·22)

- SLSA: https://slsa.dev (21)
- sigstore (cosign/Fulcio/Rekor): https://docs.sigstore.dev (21)
- GitHub Artifact Attestations: https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations (21)
- syft/grype: https://github.com/anchore/syft · https://github.com/anchore/grype (21)
- Kyverno: https://kyverno.io (21)
- Vault: https://developer.hashicorp.com/vault (22)
- External Secrets Operator: https://external-secrets.io (22)
- SOPS: https://github.com/getsops/sops · sealed-secrets: https://github.com/bitnami-labs/sealed-secrets (22)
- gitleaks: https://github.com/gitleaks/gitleaks (22)

## 모노레포·거버넌스 (20·24)

- Turborepo: https://turborepo.com/docs · Nx: https://nx.dev (20)
- Bazel: https://bazel.build (20)
- OPA/conftest: https://www.openpolicyagent.org · https://www.conftest.dev (24)
- GitHub org 룰셋·required workflows: https://docs.github.com/organizations (24)

## 기여 (26~28)

- argoproj 개발 가이드: https://argo-cd.readthedocs.io/en/stable/developer-guide/ (27)
- gitops-engine: https://github.com/argoproj/gitops-engine (27)
- Tekton community (TEP): https://github.com/tektoncd/community/tree/main/teps (28)
- Tekton catalog: https://github.com/tektoncd/catalog (28)
- CDF: https://cd.foundation (28)
- CNCF (argoproj의 집 — Part 4의 주제): https://www.cncf.io

## 사고 사례 원문 (모듈들의 "실무 사고 사례" 출처 계열)

- Knight Capital SEC 문서 (2013) — 수동 배포·무검증의 교과서 (24)
- CircleCI 인시던트 리포트 (2023-01): https://circleci.com/blog/january-4-2023-security-alert/ (22)
- Codecov 사후 보고 (2021) — CI 스크립트 변조 (21)
- xz backdoor 분석 (2024, CVE-2024-3094) — 유지보수자 신뢰 공격 (21)
- tj-actions/changed-files 사후 분석 (2025-03) — 태그 재지정·시크릿 유출 (18·21)
