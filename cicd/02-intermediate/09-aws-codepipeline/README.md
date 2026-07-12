# 09 — AWS Code 시리즈: CodePipeline이 오케스트레이션합니다

> GitHub Actions는 "이벤트 → 워크플로"의 세계였습니다. AWS Code 시리즈는 다른 철학입니다 — **CodePipeline이 지휘자**가 되어 소스(GitHub)·빌드(CodeBuild)·배포(CodeDeploy/ECS/EKS)를 스테이지로 엮습니다. CodeCommit이 신규 가입을 닫은 지금(루트 버전표), 소스는 GitHub이지만 오케스트레이션과 IAM 통합·아티팩트 흐름은 AWS 방식입니다. 이 모듈은 그 구조와, "언제 Actions 대신 이것을 쓰는가"를 다룹니다.

## 학습 목표

1. CodePipeline의 모델(스테이지·액션·아티팩트 전달)과 Actions와의 철학 차이를 압니다
2. GitHub 소스를 CodeStar Connection으로 연결합니다 (CodeCommit 종료 이후의 표준)
3. 아티팩트가 S3를 통해 스테이지 간 흐르는 구조를 이해합니다
4. IAM 역할 분리(파이프라인 역할 vs 각 액션 역할)를 설계합니다
5. "Actions vs Code 시리즈" 선택 기준을 조직 맥락으로 세웁니다

## 선행: 04(빌드·ECR), 07(OIDC/IAM 감각), eks 09(IAM) · 도구: AWS CLI, GitHub
## ⚠️ 비용: CodePipeline(활성 파이프라인당 월정액), CodeBuild(빌드 분), S3 아티팩트 — cleanup 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-pipeline-basics.md](./lab-01-pipeline-basics.md) — Connection·스테이지·아티팩트 흐름
3. [lab-02-iam-and-choice.md](./lab-02-iam-and-choice.md) — 역할 분리, Actions와 비교 결정표
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
