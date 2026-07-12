# 15 — AMG(Amazon Managed Grafana): 화면의 관리형과 통합의 자리

> 09에서 대시보드를(as code까지), 12에서 상관 배선을 배웠습니다. AMG는 그 Grafana의 관리형입니다 — 서버 운영·업그레이드·확장을 AWS가 맡고, **AWS 데이터소스들과의 통합**(AMP는 SigV4 자동, CloudWatch·X-Ray는 IAM 롤로)이 매끈하다는 것이 자체 Grafana 대비 핵심 가치입니다. 이 모듈은 워크스페이스 생성과 인증(IAM Identity Center/SAML — "누가 대시보드를 보나"의 기업 통합), 데이터소스 배선(AMP·CloudWatch·X-Ray를 한 화면에), 팀·폴더 권한, 그리고 as code의 유지(API 키·Terraform·대시보드 프로비저닝 — 09의 규율이 관리형에서도)를 다룹니다. "자체 Grafana vs AMG"의 판단으로 마무리합니다.

## 학습 목표

1. AMG 워크스페이스와 인증 모델(IAM Identity Center·SAML)을 이해합니다
2. AMP·CloudWatch·X-Ray 데이터소스를 IAM 기반으로 배선합니다 (키 없는 통합)
3. 09의 as code 규율을 AMG에서 유지하는 방법(API·프로비저닝)을 압니다
4. 팀·폴더 권한으로 조직 구조를 화면에 반영합니다
5. 자체 Grafana vs AMG의 판단 축(운영·통합·비용·확장 기능)을 세웁니다

## 선행: 09(대시보드 — 필수), 14(AMP), 13(CloudWatch) · 도구: AWS 계정(Identity Center 권장), AMP 워크스페이스
## 비용: ⚠️ 발생 — AMG는 활성 사용자당 과금. 실습 후 워크스페이스 삭제(cleanup)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-workspace-and-datasources.md](./lab-01-workspace-and-datasources.md) — 워크스페이스·인증·데이터소스 3종 배선
3. [lab-02-as-code-and-judgment.md](./lab-02-as-code-and-judgment.md) — as code 유지·권한·판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 1.5h
