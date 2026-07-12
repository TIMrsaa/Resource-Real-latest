#!/usr/bin/env bash
# 모듈 12 정리 — 로컬 실험 파일 (GitLab.com 프로젝트는 수동 삭제)
set -euo pipefail

rm -rf ~/ci-lab/glab

echo "모듈 12 정리 완료"
echo "ℹ️  GitLab.com에 프로젝트를 만들었다면 수동 삭제 (Settings → General → Delete project)"
echo "ℹ️  GitLab Runner를 EKS에 설치했다면: helm uninstall gitlab-runner -n gitlab-runners"
