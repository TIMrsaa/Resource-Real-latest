#!/usr/bin/env bash
# 모듈 23 정리 — docker 컨테이너·네트워크
set -euo pipefail

docker rm -f envoy backend-a backend-b backend-slow 2>/dev/null || true
docker network rm envoy-lab 2>/dev/null || true
rm -rf ~/cncf-lab/envoy

echo "모듈 23 정리 완료"
echo "★ 기억할 것: 메시를 운영한다는 것은 Envoy(config_dump)를 읽을 줄 안다는 것"
