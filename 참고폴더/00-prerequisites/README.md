# 00. 사전 준비 (Prerequisites)

## 학습 목표

본 커리큘럼 진행에 필요한 AWS 환경과 로컬 도구를 준비합니다.

## 진행 순서

1. [01-aws-account-setup.md](./01-aws-account-setup.md) — IAM 사용자, AWS CLI 자격증명
2. [02-local-tools.md](./02-local-tools.md) — kubectl, eksctl, helm, terraform 등 설치
3. [03-cost-guardrails.md](./03-cost-guardrails.md) — AWS Budgets 알람, cleanup 원칙
4. [04-ecr-setup.md](./04-ecr-setup.md) — ECR 리포 5개 생성, 시나리오 앱 푸시

## 소요 시간

1 ~ 2 시간 (네트워크 환경에 따라 도구 설치 시간 차이)

## 예상 비용

**0 USD** — 셋업만 진행, 실제 워크로드 리소스 미생성.
(이후 모듈에서 실제 EKS 클러스터를 띄우면서 비용이 발생합니다.)

## 자동화 스크립트

| 스크립트 | 용도 |
|---------|------|
| `scripts/check-tools.sh` | 로컬 도구 설치 여부 일괄 확인 |
| `scripts/setup-budget-alarm.sh` | AWS Budgets 알람 자동 생성 |
| `scripts/ecr-push-all.sh` | 시나리오 앱 5종 빌드 + ECR 푸시 |

## 완료 체크리스트

- [ ] IAM 사용자 생성 + AWS CLI 자격증명 등록 (`aws sts get-caller-identity` 통과)
- [ ] 로컬 도구 9종 설치 완료 (`bash scripts/check-tools.sh` 통과)
- [ ] AWS Budgets 50 USD 알람 설정
- [ ] ECR 리포지토리 5개 생성
- [ ] 시나리오 앱 5종 ECR에 푸시 완료
