#!/usr/bin/env bash
set -euo pipefail

echo "▶ 모듈 01 리소스 정리"

# 매니페스트로 만든 리소스
kubectl delete -f manifests/ --ignore-not-found

# imperative로 만든 Pod
kubectl delete pod hello-imperative --ignore-not-found

# lab-03에서 만든 NS (그 안의 모든 리소스 함께 삭제됨)
kubectl delete ns lab-team-a lab-team-b --ignore-not-found

echo "✅ 정리 완료"
echo ""
echo "다음 모듈 (02-services-networking) 으로 이동하세요."
echo "Part 1 학습이 끝났다면 클러스터 자체도 삭제하세요:"
echo "  eksctl delete cluster --name eks-study --region ap-northeast-2"
