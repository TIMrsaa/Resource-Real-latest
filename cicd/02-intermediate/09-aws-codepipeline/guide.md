# 학습 가이드 — 두 개의 철학

## Actions와 Code 시리즈는 세계관이 다릅니다

| | GitHub Actions | AWS Code 시리즈 |
|---|---|---|
| 중심 | 이벤트가 워크플로를 부름 | **파이프라인이 스테이지를 지휘** |
| 정의 | 저장소 안 YAML | AWS 리소스(콘솔/IaC) |
| 상태 | 실행마다 새로 | 파이프라인이 **지속 리소스** |
| IAM | OIDC로 assume | 파이프라인·액션이 각자 역할 |
| 잘 맞는 곳 | 코드 중심, 멀티클라우드 | AWS 깊이 통합, 규제·감사 |

둘 다 좋고 나쁨이 아니라 **맥락**입니다. AWS에 깊이 들어간 조직(모든 것이 CloudFormation, 감사가 CloudTrail 중심, IAM으로 모든 경계를 표현)에서는 Code 시리즈가 자연스럽고, 코드가 중심이고 클라우드가 배포 대상일 뿐인 조직에서는 Actions가 자연스럽습니다.

## CodeCommit 종료가 바꾼 것

루트 버전표대로 CodeCommit은 신규 가입을 닫았습니다. 그래서 이 모듈의 소스는 **GitHub**이고, 연결은 **CodeStar Connection**(구 CodeStar)입니다. AWS가 Git 호스팅에서 물러나면서 "소스는 GitHub, 나머지는 AWS"가 표준이 됐습니다 — Code 시리즈를 CodeCommit과 함께 배우던 옛 자료는 이 지점에서 낡았습니다.

## 이 파트에서 Code 시리즈의 자리

09~11은 세트입니다: 09가 오케스트레이션(CodePipeline), 10이 빌드(CodeBuild 심층), 11이 배포 전략(CodeDeploy). GitHub Actions가 이 셋을 워크플로 하나로 합치는 반면, AWS는 각각을 독립 서비스로 두고 IAM으로 엮습니다 — 그 분리가 세밀한 권한 통제와 재사용을 주는 대신 복잡도를 냅니다.

## 실용적 관점

현실의 많은 조직은 **혼용**합니다: CI는 GitHub Actions(개발자 경험), CD는 CodePipeline(프로덕션 배포의 감사·승인). 이 모듈은 순수 Code 시리즈를 배우되, 마지막에 그 혼용 패턴과 선택 기준을 정리합니다. "무엇이 우월한가"가 아니라 "우리 맥락에 무엇이 맞는가"가 lab-02의 질문입니다.
