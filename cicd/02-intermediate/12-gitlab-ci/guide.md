# 학습 가이드 — 세 번째 도구를 빠르게 배우는 법

## 이 모듈의 진짜 교훈: 이식성

CI 도구를 하나 깊이 배우면, 두 번째는 빠르고 세 번째는 더 빠릅니다 — 왜냐하면 **핵심 개념이 이식되기 때문**입니다:

```
Actions 잡        = GitLab 잡          = CodePipeline 액션    = Jenkins 스테이지
Actions 러너      = GitLab 러너        = CodeBuild            = Jenkins 에이전트
Actions artifacts = GitLab artifacts   = CodePipeline S3      = Jenkins archive
Actions matrix    = GitLab parallel    = CodeBuild batch      = Jenkins matrix
Actions needs     = GitLab needs(DAG)  = 스테이지 순서        = Jenkins 의존
Actions env/secrets = GitLab variables = SSM/Secrets          = Jenkins credentials
```

그래서 이 모듈은 GitLab CI를 "처음부터"가 아니라 **Actions와 대조**하며 배웁니다. 새 문법을 만나면 "Actions의 무엇에 해당하나"를 먼저 묻습니다 — 이 사고법이 앞으로 만날 Tekton(16), Jenkins(13), 그리고 아직 없는 도구까지 빠르게 흡수하는 능력입니다.

## 진짜 차이는 문법이 아니라 철학

GitLab의 설계 결정은 "**하나의 애플리케이션으로 전체 DevOps 라이프사이클**"입니다 — Git 호스팅, CI/CD, 컨테이너 레지스트리, 이슈, 보안 스캔, 환경 관리가 한 제품에 통합돼 있습니다. GitHub은 이것을 여러 제품(Actions, Packages, Advanced Security)의 조합으로, AWS는 여러 서비스로 풉니다.

통합의 장단:

```
장점: 한 곳에서 전부, 매끄러운 연결(파이프라인→레지스트리→환경→리뷰앱)
단점: 벤더 종속, 각 기능이 전문 도구만큼 깊지 않을 수 있음
```

eks 20의 "관리형의 양날"(App Mesh 종료)과 같은 저울질이 여기서도 — 통합을 살 때 로드맵도 함께 삽니다.

## 실습 방식

GitLab.com 무료 계정으로 실제 파이프라인을 돌리되, 각 단계에서 "이것을 Actions로 쓰면?"을 나란히 적습니다. 그 대조표가 산출물이고, 도구 독립적 사고의 증거입니다. GitLab 계정이 없으면 개념 학습으로도 목표 달성이 가능하도록 구성했습니다.
