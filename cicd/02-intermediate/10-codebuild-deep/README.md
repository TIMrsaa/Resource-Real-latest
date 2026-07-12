# 10 — CodeBuild 심층: buildspec, 캐시, VPC 빌드

> 09에서 CodeBuild를 파이프라인의 한 액션으로 스쳐 지나갔습니다. 이 모듈은 그 안으로 들어갑니다 — buildspec의 페이즈 모델, 캐시 3종(로컬/S3/커스텀), VPC 안에서 빌드하기(08의 self-hosted 러너와 같은 요구), 그리고 컴퓨트 타입 선택의 경제학. GitHub Actions의 러너에 대응하는 AWS의 빌드 실행 환경을 해부합니다.

## 학습 목표

1. buildspec의 페이즈 모델(install/pre_build/build/post_build)과 실패 처리를 압니다
2. 캐시 3종(local layer / S3 / 커스텀)을 구분하고 04의 레이어 캐시 원리를 적용합니다
3. VPC 구성으로 빌드가 프라이빗 리소스에 접근하게 합니다 — 그 대가(NAT)까지
4. 컴퓨트 타입과 요금 구조로 빌드 비용을 설계합니다
5. CodeBuild 역할에서 OIDC 아닌 서비스 역할로 ECR/EKS에 배포하는 경로를 압니다

## 선행: 04(빌드·레이어 캐시), 09(CodePipeline·CodeBuild 액션), eks 16(NAT·IP) · 도구: AWS CLI
## ⚠️ 비용: CodeBuild 빌드 분 + (VPC 빌드 시) NAT 처리 — cleanup 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-buildspec-cache.md](./lab-01-buildspec-cache.md) — 페이즈, 캐시 3종 실측
3. [lab-02-vpc-and-deploy.md](./lab-02-vpc-and-deploy.md) — VPC 빌드, ECR 푸시, EKS 배포
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
