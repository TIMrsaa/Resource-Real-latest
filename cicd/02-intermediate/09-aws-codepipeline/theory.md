# 이론 — 파이프라인 모델, 아티팩트 흐름, IAM 분리

> **🌱 17세 눈높이 비유: 공장 컨베이어 벨트**
> - **GitHub Actions** = 주문이 오면 작업자 한 명이 처음부터 끝까지 (이벤트 → 워크플로)
> - **CodePipeline** = 컨베이어 벨트: 각 **구역(스테이지)**에 전문 작업자가 있고, 반제품(아티팩트)이 상자에 담겨 다음 구역으로 흘러갑니다
> - **아티팩트 = 상자** = 소스 코드 → (빌드 구역) → 이미지 정보 → (배포 구역). 상자는 **창고(S3)**를 거쳐 전달됩니다
> - **CodeStar Connection** = 외부 부품업체(GitHub)와 공장을 잇는 전용 통로
> - **IAM 역할 분리** = 각 구역 작업자에게 **그 구역 열쇠만** 줍니다 — 빌드 작업자가 배포실 열쇠를 갖지 않습니다

---

## 1. 파이프라인 모델 — 스테이지·액션·전이

```
Pipeline
 ├─ Stage: Source
 │    └─ Action: GitHub (CodeStar Connection) → SourceArtifact
 ├─ Stage: Build
 │    └─ Action: CodeBuild(SourceArtifact) → BuildArtifact
 ├─ Stage: Deploy-Staging
 │    └─ Action: ECS/EKS/CodeDeploy(BuildArtifact)
 ├─ Stage: Approval          ← 수동 승인 (01의 배포 버튼)
 │    └─ Action: Manual approval (SNS 알림)
 └─ Stage: Deploy-Prod
      └─ Action: ...
```

- **스테이지는 순차**, 한 스테이지의 여러 액션은 `runOrder`로 병렬/순차 지정
- 스테이지가 실패하면 파이프라인이 멈춥니다 (전이 비활성화 = 수동 게이트)
- 소스 변경이 자동 트리거(Connection의 웹훅) 또는 수동 릴리스

## 2. 아티팩트 흐름 — S3가 컨베이어입니다

```
Source 액션 → SourceArtifact (S3에 zip으로 저장)
                    ↓ 입력
Build 액션 → BuildArtifact (S3에 저장)
                    ↓ 입력
Deploy 액션이 소비
```

핵심 개념:

- 모든 아티팩트는 **파이프라인의 아티팩트 버킷(S3)** 을 거칩니다 — 스테이지 간 직접 전달이 아닙니다
- 각 액션은 `inputArtifacts`와 `outputArtifacts`를 선언 — 이름으로 연결
- 이 S3 버킷은 **KMS 암호화**해야 합니다(소스 코드·빌드 산출물이 담깁니다). 그리고 접근 권한이 파이프라인 IAM의 핵심

**Actions와의 대조**: Actions는 잡 간 전달이 outputs/artifacts(03)였다면, CodePipeline은 **모든 것이 S3 아티팩트**입니다 — 더 무겁지만 각 단계의 산출물이 명시적으로 보관·감사됩니다.

## 3. CodeStar Connection — GitHub 접합

```
aws codestar-connections create-connection --provider-type GitHub --connection-name X
  → 상태 PENDING (콘솔에서 GitHub OAuth 승인 필요 — 한 번)
  → AVAILABLE
```

- Connection은 GitHub App 기반 — PAT를 파이프라인에 저장하지 않습니다(07의 사상과 통합니다)
- 소스 액션이 이 Connection ARN으로 저장소·브랜치를 참조
- 웹훅으로 push를 감지해 파이프라인 자동 시작

## 4. IAM 분리 — 두 층의 역할

```
① 파이프라인 서비스 역할 (CodePipeline 자신)
   - 아티팩트 S3 read/write
   - 각 액션(CodeBuild, ECS 등)을 호출할 권한
   - Connection 사용 권한

② 각 액션의 역할 (예: CodeBuild 서비스 역할)
   - 그 액션이 실제로 하는 일의 권한 (ECR push, 로그)
   - 파이프라인 역할과 분리 = 최소권한
```

이 분리가 Code 시리즈의 강점이자 복잡도입니다: 빌드가 탈취돼도 배포 권한이 없고, 각 경계가 IAM으로 명시됩니다 — 대신 역할이 여러 개가 됩니다. eks 09의 최소권한 원칙이 CI/CD 파이프라인 스케일로 적용된 것.

## 5. 정의 방식 — 콘솔 vs IaC

| 방식 | 특징 |
|------|------|
| 콘솔 | 빠른 시작, 클릭. 재현·버전관리 안 됨 |
| **CloudFormation/CDK** | 파이프라인 자체가 코드 — DR(eks 24)·감사·리뷰 |
| Terraform | 멀티클라우드 조직의 표준 |

프로덕션 파이프라인은 반드시 IaC로 — "파이프라인을 배포하는 파이프라인"(self-mutating pipeline, CDK Pipelines)이 성숙한 패턴입니다. eks 23의 "선언이 진실"이 여기서도.

## 6. Actions vs Code 시리즈 — 결정 기준

| 기준 | Actions 유리 | Code 시리즈 유리 |
|------|-------------|-----------------|
| 개발자 경험 | ✔ (저장소 안 YAML, PR 통합) | |
| 멀티클라우드 | ✔ | (AWS 종속) |
| AWS 깊은 통합 | | ✔ (IAM·CloudTrail·이벤트브리지) |
| 규제·감사 | | ✔ (모든 것이 AWS 리소스·로그) |
| 승인 거버넌스 | environments(06) | ✔ (수동 승인·SNS·조직 정책) |
| 생태계 | ✔ (마켓플레이스) | (제한적) |
| 배포 대상이 AWS만 | 둘 다 | ✔ |

현실 권장: **CI는 Actions, CD는 상황에 따라.** AWS 규제 환경의 프로덕션 배포는 CodePipeline의 감사·승인이, 개발 속도는 Actions가 낫습니다. 혼용이 흔합니다.

## 7. 소스/도구에서 확인하기

- CodePipeline 문서: https://docs.aws.amazon.com/codepipeline/
- CodeStar Connections (GitHub): "Connections for GitHub"
- CDK Pipelines(self-mutating): https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.pipelines-readme.html
- CodePipeline은 오픈소스가 아닙니다 — 기여 통로는 containers-roadmap 방식(eks 27)

## 요약 카드

| 질문 | 답 |
|------|----|
| 철학 차이? | 이벤트→워크플로(Actions) vs **파이프라인이 스테이지 지휘**(Code) |
| 아티팩트 전달? | 모든 것이 **S3 아티팩트 버킷** 경유 (KMS 암호화 필수) |
| GitHub 소스 연결? | CodeStar Connection (PAT 아님, GitHub App) |
| IAM 구조? | 파이프라인 역할 + **액션별 역할**(최소권한 분리) |
| 정의 방식? | 프로덕션은 IaC (CDK Pipelines의 self-mutating) |
| CodeCommit? | 신규 불가 — 소스는 GitHub |
| 선택 기준? | CI=Actions, CD=규제/AWS깊이면 Code 시리즈 (혼용 흔함) |
