#!/usr/bin/env bash
# 모듈 28 정리 — kind 클러스터, 클론
set -euo pipefail

kind delete cluster --name tekton-dev 2>/dev/null || true
rm -rf ~/contrib/pipeline ~/contrib/community ~/contrib/my-catalog-task

echo "모듈 28 정리 완료"
echo "ℹ️  실제 catalog 기여를 이어간다면 my-catalog-task는 보존 후 fork 저장소로 이동"
echo "ℹ️  ~/contrib 비었으면 rmdir ~/contrib 로 마무리"
