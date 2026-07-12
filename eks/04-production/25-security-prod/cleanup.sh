#!/usr/bin/env bash
# 모듈 25 정리 — 정책/CSI/시크릿/IAM (hop limit은 되돌리지 않습니다 — 보안 개선분)
set -euo pipefail
export AWS_REGION=ap-northeast-2
CLUSTER=k8s-study
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

kubectl delete validatingadmissionpolicybinding trusted-registries --ignore-not-found
kubectl delete validatingadmissionpolicy trusted-registries --ignore-not-found
kubectl delete namespace seclab --ignore-not-found

kubectl delete -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml 2>/dev/null || true
helm uninstall csi-secrets-store -n kube-system 2>/dev/null || true

eksctl delete podidentityassociation --cluster $CLUSTER --region $AWS_REGION \
  --namespace seclab --service-account-name app-sa 2>/dev/null || true
aws iam detach-role-policy --role-name SecretsCsiLab \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/SecretsCsiLab 2>/dev/null || true
aws iam delete-role --role-name SecretsCsiLab 2>/dev/null || true
aws iam delete-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/SecretsCsiLab 2>/dev/null || true

aws secretsmanager delete-secret --region $AWS_REGION --secret-id eks-lab/db \
  --force-delete-without-recovery 2>/dev/null || true
rm -f sm-policy.json sm-trust.json

echo "모듈 25 정리 완료 — ⚠️ IMDS hop limit=1은 의도적으로 유지(보안 개선). 되돌리려면 modify-instance-metadata-options --http-put-response-hop-limit 2"
