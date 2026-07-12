#!/usr/bin/env bash
set -euo pipefail

REQUIRED=(aws kubectl eksctl helm terraform go docker jq yq k9s stern)
MISSING=()

for cmd in "${REQUIRED[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING+=("$cmd")
  fi
done

if (( ${#MISSING[@]} > 0 )); then
  echo "❌ 다음 도구가 설치되지 않았습니다: ${MISSING[*]}"
  echo "→ 02-local-tools.md를 참고해 설치하세요."
  exit 1
fi

echo "✅ 모든 도구가 설치됨"
echo ""
echo "버전:"
aws --version
kubectl version --client --output=yaml 2>/dev/null | head -3 || kubectl version --client
eksctl version
helm version --short
terraform version | head -1
go version
docker --version
jq --version
yq --version
