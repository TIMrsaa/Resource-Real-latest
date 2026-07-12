#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
EMAIL="${1:?사용법: $0 <알람-수신-이메일> [예산-USD=50]}"
BUDGET_AMOUNT="${2:-50}"

cat > /tmp/budget.json <<EOF
{
  "BudgetName": "eks-study-budget",
  "BudgetLimit": {"Amount": "${BUDGET_AMOUNT}", "Unit": "USD"},
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
EOF

cat > /tmp/notifications.json <<EOF
[{
  "Notification": {
    "NotificationType": "ACTUAL",
    "ComparisonOperator": "GREATER_THAN",
    "Threshold": 80,
    "ThresholdType": "PERCENTAGE"
  },
  "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "${EMAIL}"}]
}]
EOF

aws budgets create-budget \
  --account-id "${ACCOUNT_ID}" \
  --budget file:///tmp/budget.json \
  --notifications-with-subscribers file:///tmp/notifications.json

echo "✅ ${BUDGET_AMOUNT} USD 예산 알람 생성 완료 (수신: ${EMAIL})"
echo "   80% 도달 시 ${EMAIL} 로 알림 발송"
