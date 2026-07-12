#!/usr/bin/env bash
# 모듈 22 정리 — kind 클러스터, 로컬 실습 파일
set -euo pipefail

kind delete cluster --name secrets 2>/dev/null || true
rm -rf ~/ci-lab/secrets

echo "모듈 22 정리 완료"
echo "⚠️  age.key 등 실습 키 파일이 다른 곳에 복사됐다면 함께 삭제"
echo "ℹ️  실습에 실제 시크릿을 쓰지 않았는지 확인 (형식만 재현한 가짜 값이어야 함)"
