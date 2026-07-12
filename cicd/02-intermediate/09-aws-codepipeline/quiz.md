# 자가 점검 퀴즈

**Q1.** GitHub Actions와 AWS Code 시리즈의 철학 차이를 "무엇이 중심인가"로 설명하세요.

**Q2.** CodePipeline에서 스테이지 간 아티팩트는 어떻게 전달되는가요? Actions의 방식과 비교하세요.

**Q3.** CodeCommit 종료가 소스 연결에 미친 영향과, 지금의 표준 방식은?

**Q4.** CodePipeline의 IAM 두 층을 설명하고, 이 분리가 주는 이점과 대가는?

**Q5.** 아티팩트 S3 버킷을 반드시 KMS 암호화해야 하는 이유는?

**Q6.** 파이프라인을 콘솔이 아니라 IaC로 정의해야 하는 이유 세 가지는?

**Q7.** 수동 승인 스테이지는 01의 어떤 개념에 대응하며, GitHub Actions에서는 무엇으로 구현하나요?

**Q8.** "CI=Actions, CD=CodePipeline" 혼용이 정당한 조직 맥락 두 가지를 들라.

---

## 정답

**A1.** Actions는 **이벤트가 워크플로를 부르는** 모델(저장소 안 YAML, 실행마다 새로). Code 시리즈는 **파이프라인이라는 지속 리소스가 스테이지를 지휘하는** 모델(소스·빌드·배포를 독립 서비스로 두고 오케스트레이션). 전자는 코드 중심, 후자는 AWS 리소스 중심.

**A2.** 모든 아티팩트가 파이프라인의 **S3 아티팩트 버킷을 경유**합니다(각 액션이 inputArtifacts/outputArtifacts를 이름으로 선언). Actions는 잡 간 outputs(작은 값)/artifacts(파일)로 더 경량 전달. Code 시리즈는 무겁지만 각 단계 산출물이 명시적으로 보관·감사됩니다.

**A3.** CodeCommit이 신규 가입을 닫아 소스는 **GitHub**이 표준이 됐고, 연결은 **CodeStar Connection**(GitHub App 기반)으로 합니다 — PAT를 파이프라인에 저장하지 않으며, 콘솔에서 한 번 OAuth 승인해야 AVAILABLE이 됩니다.

**A4.** ① 파이프라인 서비스 역할(오케스트레이션 — 아티팩트 S3, 액션 호출, Connection 사용). ② 각 액션의 역할(그 액션이 실제로 하는 일 — 예: CodeBuild의 ECR push·로그). 이점: 스테이지별 최소권한 경계(빌드 탈취가 배포로 안 번짐). 대가: 역할이 여러 개가 되는 복잡도.

**A5.** 그 버킷에는 **소스 코드 전체와 빌드 산출물**이 담깁니다 — 코드에 섞인 시크릿, 빌드 로그, 중간 아티팩트가 모두 여기에. 암호화(KMS)와 접근 제한(파이프라인·액션 역할만)이 없으면 전체 코드베이스와 잠재 시크릿이 노출됩니다.

**A6.** ① 재현성/DR(eks 24 — 재건할 선언이 있어야) ② 버전관리·리뷰(누가 언제 스테이지를 바꿨나) ③ 감사·거버넌스(변경이 PR을 거침). 성숙한 형태는 CDK Pipelines의 self-mutating(파이프라인 변경도 파이프라인을 거침).

**A7.** 01의 **Continuous Delivery**("배포 버튼은 사람이 누른다") — 자동으로 준비하되 프로덕션 전이는 사람이 결정. GitHub Actions에서는 **environment의 required reviewers**(06)로 구현합니다.

**A8.** ① 규제 산업: 프로덕션 배포의 CloudTrail 기반 감사와 조직 정책 승인이 요구되어 CD는 CodePipeline, 개발 속도를 위해 CI는 Actions. ② 승인 주체가 개발팀 밖(보안·운영): CodePipeline의 조직 정책·SNS 승인이 그 거버넌스에 맞고, 개발자 경험은 Actions로. 두 경우 모두 Actions가 CodePipeline을 트리거하는 방식으로 연결합니다.
