#!/usr/bin/env bash
# 모듈 15 정리
set -euo pipefail
kubectl delete namespace shop monitoring --ignore-not-found
kubectl delete pod outsider --ignore-not-found
echo "모듈 15 정리 완료 (VPC CNI 정책 기능은 유지 — 끄려면:"
echo "  aws eks update-addon --cluster-name k8s-study --addon-name vpc-cni --configuration-values '{\"enableNetworkPolicy\":\"false\"}' )"
