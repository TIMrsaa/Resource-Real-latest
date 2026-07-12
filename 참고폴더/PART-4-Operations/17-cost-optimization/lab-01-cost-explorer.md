# Lab 01 — AWS Cost Explorer 활용

> **🌱 핵심 개념 미리보기**
> - **Cost Explorer**: AWS 가 매시간(약 24h 지연) 청구 데이터를 집계해 주는 분석 도구. API + 콘솔 둘 다 제공.
> - **UnblendedCost**: 실제 그 계정에 청구된 금액 (RI/Savings Plan 할인 미배분). 가장 직관적인 비용 지표.
> - **Granularity**: HOURLY / DAILY / MONTHLY. HOURLY 는 별도 활성화 필요 + 추가 요금.
> - **Cost Allocation Tag**: 리소스 태그를 비용 차원으로 승격. 활성화 후 24h 뒤부터 group-by 가능.
> - **AWS Budgets**: 예산 임계치 도달 시 알람. Cost Explorer 와 별개 서비스 (학습 환경 보호용).

## 1. CLI 로 일별 EC2 비용

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-7d +%F),End=$(date -u +%F) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --query 'ResultsByTime[*].[TimePeriod.Start,Total.UnblendedCost.Amount]' \
  --output table
```

기대: 7일치 일별 EC2 비용. (학습 시작 후 며칠 안 됐으면 데이터 부족)

> **🧠 왜 비용이 0 이거나 늦게 보이나**
> Cost Explorer 의 데이터는 **24시간 지연**이 일반적. 어제 EC2 띄웠어도 오늘 새벽까지는 0 으로 보일 수 있음.
> 또 `UnblendedCost` 는 청구 발생 시점 기준 — Spot 인스턴스가 1분 만에 끝났다면 1시간 단위로 반올림된 청구가 나오기까지 시간차 있음.
> 학습 환경에서 "왜 비용이 안 보이지?" 하면 거의 다 이 지연 탓.

## 2. 서비스별 누적

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-30d +%F),End=$(date -u +%F) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output table
```

## 3. 사용 유형별 (UsageType)

NAT GW / EBS / 데이터 전송을 분리해 보기:
```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-7d +%F),End=$(date -u +%F) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=USAGE_TYPE \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --query 'ResultsByTime[].Groups[?Metrics.UnblendedCost.Amount>`0.01`].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output text | sort | uniq -c | sort -rn | head
```

기대: BoxUsage:t3.medium / NatGateway-Hours / NatGateway-Bytes / DataTransfer-Out 등.

> **🧠 NAT GW 의 두 가지 청구 — 학습 환경 비용 1위 후보**
> - `NatGateway-Hours`: 게이트웨이 1개당 시간당 약 $0.045 (서울). 24h × 30일 = ~$32/월.
> - `NatGateway-Bytes`: 처리 GB 당 $0.045. ECR pull, 외부 API 호출 다 여기로 잡힘.
>
> Multi-AZ 로 NAT 3개 띄우면 가만히 있어도 ~$100/월. **학습 종료 후 AZ당 NAT 1개 → 0개 (VPC Endpoint 대체)** 가 절약 1순위.

## 4. 콘솔 활용

CloudConsole → Cost Explorer → "Cost and usage reports".

**유용한 필터**:
- Service = EC2 + EKS + Load Balancer
- Tag = `Project: eks-study` (리소스 태깅 후)
- Dimension: Linked Account / Usage Type / Instance Type

**그룹화** 추천:
- Linked Account (멀티 계정)
- Service
- Usage Type
- Tag

## 5. 태그 기반 비용 분리

리소스에 `Project=<name>` 태그를 붙이면 Cost Explorer 에서 분리 추적 가능. Karpenter 의 EC2NodeClass 의 `tags` 필드 활용:

```yaml
spec:
  tags:
    Project: eks-study
    Team: platform
    Environment: learning
```

태그 활성화 (Cost Allocation Tags):
1. Console → Billing → Cost allocation tags
2. `Project`, `Team` 등 활성화
3. 24시간 후 Cost Explorer 에서 사용 가능

> **🧠 태그를 붙였는데 안 보이는 진짜 이유들**
> 1. **활성화 안 함**: 리소스에 태그만 달면 끝이 아니라 Billing 콘솔에서 "Activate" 클릭해야 차원으로 잡힘.
> 2. **활성화 후 24h 미경과**: 활성화 시점부터 미래 데이터에만 적용. 과거 비용엔 소급 X.
> 3. **태그 키 대소문자 구분**: `project` 와 `Project` 는 다른 태그. 팀 컨벤션 통일 필수.
> 4. **하위 리소스 미상속**: ASG 에 태그 달아도 EC2 인스턴스에 자동 전파되지 않음 (Karpenter 의 `tags` 는 EC2 에 직접 전파).

## 6. AWS Budgets 알람 (이미 00-prerequisites 에서 설정)

```bash
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) \
  --query 'Budgets[].[BudgetName,BudgetLimit.Amount,BudgetLimit.Unit]' --output table
```

추가 알람 — 일일 비용 (학습 환경 보호):
```bash
cat > /tmp/daily-budget.json <<EOF
{
  "BudgetName": "eks-study-daily",
  "BudgetLimit": {"Amount": "5", "Unit": "USD"},
  "TimeUnit": "DAILY",
  "BudgetType": "COST"
}
EOF
# 알람 추가는 setup-budget-alarm.sh 참고
```

> **🧠 Budgets 와 Cost Explorer 의 차이**
> - **Cost Explorer**: 사후 분석. "이번 달에 얼마 썼나" 보고 의사결정.
> - **Budgets**: 사전 예방. 임계치(예: 50%/80%/100%) 도달 시 SNS/이메일 알람.
>
> 학습 환경에선 **DAILY $5** 또는 **MONTHLY $50** 짜리 예산이 안전망. 새벽에 NAT GW 를 깜빡 잊고 안 지웠을 때 알람 한 통이 수십 달러 절약해줌.

## 학습 확인 질문

1. Cost Explorer 의 데이터는 얼마나 자주 갱신되나?
2. NAT GW 의 두 가지 비용 항목은?
3. 태그를 붙였는데 Cost Explorer 에서 안 보이는 이유는?

다음: [lab-02-rightsizing.md](./lab-02-rightsizing.md)
