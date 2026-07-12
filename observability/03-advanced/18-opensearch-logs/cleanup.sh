#!/usr/bin/env bash
# 모듈 18 정리 — kind 클러스터 (AWS 도메인을 썼다면 반드시 삭제 — 시간당 과금!)
set -euo pipefail

kind delete cluster --name opensearch 2>/dev/null || true
rm -f /tmp/fb-os.yaml 2>/dev/null || true

echo "AWS OpenSearch Service 도메인을 생성했다면 콘솔/CLI로 삭제를 확인하세요 (시간당 과금)."
echo "모듈 18 정리 완료"
echo "★ 기억할 것: 색인은 비쌉니다 — 검색할 것만 색인하고(절제의 네 번째 반복), 검색 필요 없는 보관은 S3로"
