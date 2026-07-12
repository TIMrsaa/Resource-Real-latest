#!/usr/bin/env bash
# 모듈 13 정리 — 로컬 Jenkins 컨테이너와 볼륨
set -euo pipefail

docker rm -f jenkins-lab 2>/dev/null || true
docker volume rm jenkins_home 2>/dev/null || true
rm -rf ~/ci-lab/jenkins

echo "모듈 13 정리 완료 — 중급 트랙(06~13) 졸업"
echo "다음: 고급(14~20) — GitOps(ArgoCD/Flux)가 배포 패러다임을 push에서 pull로 바꾼다"
