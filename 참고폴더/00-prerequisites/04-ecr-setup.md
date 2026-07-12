# 04. ECR 셋업 및 시나리오 앱 푸시

Part 2부터 EKS 클러스터에 시나리오 MSA 앱을 배포하려면, ECR(Elastic Container Registry)에 미리 이미지를 푸시해 두는 것이 편합니다.

## 1. ECR 리포지토리 5개 생성

```bash
REGION=ap-northeast-2
for svc in order-service payment-service user-service notification-service frontend; do
  aws ecr create-repository \
    --repository-name eks-study/$svc \
    --region $REGION \
    --image-scanning-configuration scanOnPush=true || true
done
```

## 2. 생성 확인

```bash
aws ecr describe-repositories \
  --query 'repositories[?starts_with(repositoryName, `eks-study/`)].[repositoryName,repositoryUri]' \
  --output table
```

## 3. 도커 로그인

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
```

기대 출력: `Login Succeeded`

## 4. 시나리오 앱 빌드 + 푸시

자동화 스크립트:
```bash
bash scripts/ecr-push-all.sh
```

이 스크립트는 다음을 수행합니다:
1. ECR 로그인
2. `scenarios/` 안의 5개 서비스 도커 이미지 빌드
3. `${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/eks-study/<서비스>:latest` 로 푸시

## 5. 푸시 확인

```bash
for svc in order-service payment-service user-service notification-service frontend; do
  aws ecr describe-images \
    --repository-name eks-study/$svc \
    --query 'imageDetails[].[imageTags[0],imagePushedAt]' --output table
done
```

## 이미지 라이프사이클 (선택)

저장 비용 절감을 위해 lifecycle 정책 설정 권장:

```bash
cat > /tmp/lifecycle.json <<'EOF'
{
  "rules": [{
    "rulePriority": 1,
    "description": "Keep only last 5 images",
    "selection": {
      "tagStatus": "any",
      "countType": "imageCountMoreThan",
      "countNumber": 5
    },
    "action": {"type": "expire"}
  }]
}
EOF

for svc in order-service payment-service user-service notification-service frontend; do
  aws ecr put-lifecycle-policy \
    --repository-name eks-study/$svc \
    --lifecycle-policy-text file:///tmp/lifecycle.json
done
```

## 트러블슈팅

| 증상 | 해결 |
|------|------|
| `denied: Your authorization token has expired` | `aws ecr get-login-password ...` 재실행 (12시간마다 만료) |
| `name unknown: The repository ... does not exist` | 1단계 리포 생성 누락 |
| `error pulling image manifest` (배포 시) | EKS 노드의 IAM Role에 `AmazonEC2ContainerRegistryReadOnly` 정책 필요 |

## 다음 단계

→ Part 1로 진행: [`PART-1-Kubernetes-Basics/01-core-concepts/`](../PART-1-Kubernetes-Basics/01-core-concepts/)
