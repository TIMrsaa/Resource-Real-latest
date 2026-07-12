# 학습 가이드 — 러너를 바꿔도 원리는 같습니다

## 04·08과 같은 문제, 다른 도구

CodeBuild는 AWS의 빌드 실행 환경입니다 — GitHub Actions 러너(03)에 대응합니다. 그리고 러너가 바뀌어도 우리가 04·08에서 배운 것은 그대로 유효합니다:

- **레이어 캐시의 규칙**(04): buildspec의 캐시가 히트하려면 여전히 "변경 빈도 낮은 것부터"
- **VPC 접근의 요구**(08): 프라이빗 DB·리소스에 붙는 빌드는 CodeBuild도 VPC 구성이 필요
- **재현성 vs 캐시**(03): CodeBuild도 기본은 깨끗한 환경, 캐시는 명시적으로

그래서 이 모듈은 새 개념을 최소화하고, **익숙한 원리가 CodeBuild 문법으로 어떻게 표현되는지**에 집중합니다. 새로운 것은 buildspec의 페이즈 모델과 AWS 특유의 캐시·컴퓨트·VPC 구성뿐입니다.

## buildspec — 워크플로 YAML의 사촌

Actions 워크플로가 잡·스텝이라면, buildspec은 **페이즈**입니다:

```
install → pre_build → build → post_build   (+ artifacts, cache 선언)
```

Actions와 다른 점: 페이즈 실패 시의 동작이 명시적이고(`on-failure`), artifacts·reports가 CodePipeline/테스트 리포트와 통합됩니다. 같은 점: 명령을 순서대로 실행하고, 캐시를 명시하며, 환경변수/시크릿을 다룹니다.

## VPC 빌드의 무게

08에서 self-hosted 러너를 VPC에 넣은 이유(프라이빗 리소스 접근)와 그 대가(격리·보안 책임)를 배웠습니다. CodeBuild의 VPC 구성도 같은 거래입니다 — 다만 CodeBuild는 관리형이라 격리는 AWS가 주고, 우리가 지는 대가는 **NAT 처리 비용과 IP 소비**(eks 16)입니다. VPC 빌드는 "인터넷 없는 빌드"가 아니라 "프라이빗 서브넷에서 NAT를 거치는 빌드"임을 이해하는 것이 lab-02의 핵심.

## 이 모듈의 실용적 목표

CodeBuild를 GitHub Actions 대신 CI로 쓸 수도 있지만(webhook 트리거), 현실적으로는 **09의 파이프라인 안 빌드 단계**이거나 **AWS 깊은 통합이 필요한 빌드**입니다. lab은 그 맥락에서 진행합니다.
