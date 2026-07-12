#!/usr/bin/env bash
# 모듈 13 정리 — ⚠️ CloudWatch 비용 발생 리소스 정리
set -euo pipefail

CLUSTER=${CLUSTER:-my-eks}
REGION=${REGION:-ap-northeast-2}

# 테스트 워크로드
kubectl delete deployment web logger --ignore-not-found 2>/dev/null || true

# Container Insights 애드온 제거
aws eks delete-addon --cluster-name "$CLUSTER" --region "$REGION" \
  --addon-name amazon-cloudwatch-observability 2>/dev/null || true

# 컨트롤 플레인 로깅 off (audit·authenticator)
eksctl utils update-cluster-logging --cluster "$CLUSTER" --region "$REGION" \
  --disable-types all --approve 2>/dev/null || true

# 알람 삭제
aws cloudwatch delete-alarms --region "$REGION" \
  --alarm-names "log-ingest-spike-$CLUSTER" 2>/dev/null || true

# 로그 그룹 삭제 (저장 비용 차단)
for g in application dataplane host performance; do
  aws logs delete-log-group --region "$REGION" \
    --log-group-name "/aws/containerinsights/$CLUSTER/$g" 2>/dev/null || true
done
aws logs delete-log-group --region "$REGION" \
  --log-group-name "/aws/eks/$CLUSTER/cluster" 2>/dev/null || true

echo "모듈 13 정리 완료 — CloudWatch 로그 그룹·애드온·알람 삭제, 컨트롤 플레인 로깅 off"
echo "★ 기억할 것: 관리형의 장애 모드는 다운이 아니라 청구서입니다 — ingest ≫ 저장, 통제는 보내기 전(수문)"
