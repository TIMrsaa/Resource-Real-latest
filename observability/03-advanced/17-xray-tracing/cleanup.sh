#!/usr/bin/env bash
# 모듈 17 정리 — ⚠️ X-Ray 샘플링 규칙 원복 + 16의 정리 연계
set -euo pipefail

REGION=${REGION:-ap-northeast-2}

# 부스트 샘플링 규칙 제거 (남아 있으면 과금 지속)
aws xray delete-sampling-rule --region "$REGION" --rule-name order-path-boost 2>/dev/null || true

# 16의 cleanup(ADOT·IRSA·EMF)을 아직 안 했다면 실행
echo "16의 cleanup.sh(ADOT·IRSA) 실행 여부를 확인하세요."

echo "모듈 17 정리 완료 — X-Ray 샘플링 규칙 원복"
echo "★ 기억할 것: X-Ray의 영토는 앱 밖 구간(ALB·SQS·Lambda) — 트레이스의 공백이 어디인지 아는 것이 스택 이해다"
