#!/usr/bin/env bash
# 모듈 11 정리 — 배포 실험 네임스페이스
set -euo pipefail

kubectl delete namespace deploylab --ignore-not-found

echo "모듈 11 정리 완료 — AWS Code 시리즈(09~11) 완료"
echo "다음: 12(GitLab CI), 13(Jenkins) — GitHub/AWS 밖의 CI 생태계"
