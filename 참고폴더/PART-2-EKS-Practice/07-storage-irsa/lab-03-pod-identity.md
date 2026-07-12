# Lab 03 — Pod Identity (IRSA의 진화형)

## 학습 확인 포인트

- [ ] Pod Identity Agent addon 설치
- [ ] Trust Policy가 IRSA 보다 단순함을 봤다
- [ ] 같은 IAM Role 을 여러 클러스터/SA 에 재사용 가능

> **🌱 Pod Identity 가 왜 등장했나?**
> IRSA의 약점:
> 1. **클러스터마다 OIDC URL 다름** → IAM Role의 Trust Policy가 클러스터 종속
>    → 같은 Role을 다른 클러스터에서 쓰려면 Trust 수정 필수
> 2. **SA 추가 시마다 Trust 정책 수정** (sub 조건에 추가)
> 3. **OIDC provider IAM 등록 필수** (수가 많아지면 IAM 제한 도달)
>
> Pod Identity는 이걸 EKS API로 해결:
> - Trust 정책: `pods.eks.amazonaws.com` 만 신뢰 (한 줄, 클러스터 무관)
> - 매핑 관계는 별도 EKS API (`PodIdentityAssociation`) 로 관리
>
> 출시: 2023년 11월 (re:Invent). 신규 프로젝트 권장.

## 1. EKS Pod Identity Agent addon 설치

```bash
eksctl create addon --cluster eks-study \
  --name eks-pod-identity-agent \
  --region ap-northeast-2

kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

기대: 노드별 1개 Pod (DaemonSet).

> **🧠 Agent가 하는 일**
> Pod Identity 동작 시 자격증명 발급 흐름:
> ```
>   Pod (SA: pod-identity-sa)
>     ↓ AWS SDK가 환경변수 발견
>   AWS_CONTAINER_CREDENTIALS_FULL_URI=http://169.254.170.23/...
>     ↓ HTTP GET
>   Pod Identity Agent (DaemonSet의 Pod, hostNetwork=true)
>     ↓ EKS API에 PodIdentityAssociation 조회
>   "이 SA에 매핑된 Role은 X" → AssumeRole
>     ↓
>   임시 자격증명 반환
> ```
> 즉 **각 노드의 Agent가 자격증명 프록시 역할**. IRSA는 토큰을 SDK가 직접 STS에 전달했다면, Pod Identity는 노드의 Agent가 중간에서 처리.

## 2. Pod Identity 용 IAM Role 생성

Trust Policy 가 IRSA 보다 훨씬 단순:

```bash
cat > /tmp/pod-identity-trust.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "pods.eks.amazonaws.com"},
    "Action": ["sts:AssumeRole", "sts:TagSession"]
  }]
}
EOF

aws iam create-role \
  --role-name PodIdentityS3Reader \
  --assume-role-policy-document file:///tmp/pod-identity-trust.json

aws iam attach-role-policy \
  --role-name PodIdentityS3Reader \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

> **차이점**: OIDC issuer URL 도, sub condition 도 없음. `pods.eks.amazonaws.com` Service 만 신뢰.

> **🧠 IRSA Trust vs Pod Identity Trust 비교**
>
> IRSA Trust (10줄):
> ```json
> {
>   "Principal": {"Federated": "arn:aws:iam::ACC:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID"},
>   "Action": "sts:AssumeRoleWithWebIdentity",
>   "Condition": {
>     "StringEquals": {
>       "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub":
>         "system:serviceaccount:NS:SA"
>     }
>   }
> }
> ```
>
> Pod Identity Trust (3줄):
> ```json
> {
>   "Principal": {"Service": "pods.eks.amazonaws.com"},
>   "Action": ["sts:AssumeRole", "sts:TagSession"]
> }
> ```
>
> = 클러스터 ID 박힘 vs 클러스터 무관 (재사용 ↑)

## 3. ServiceAccount 만들고 Pod Identity Association 생성

```bash
kubectl create sa pod-identity-sa
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws eks create-pod-identity-association \
  --cluster-name eks-study \
  --namespace default \
  --service-account pod-identity-sa \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/PodIdentityS3Reader \
  --region ap-northeast-2
```

> **🧠 PodIdentityAssociation 이라는 새 EKS API 객체**
> "이 클러스터의 NS/SA 조합에 이 IAM Role 매핑" 을 EKS가 직접 관리.
> SA 어노테이션 X, Trust Policy 수정 X. 모든 매핑 정보가 이 객체 하나에.
>
> 보기:
> ```bash
> aws eks list-pod-identity-associations --cluster-name eks-study
> ```

## 4. Pod 실행

```bash
cat > /tmp/pi-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pi-test
spec:
  serviceAccountName: pod-identity-sa
  containers:
    - name: aws
      image: amazon/aws-cli:2.15.0
      command: ["sleep", "3600"]
EOF

kubectl apply -f /tmp/pi-pod.yaml
kubectl wait --for=condition=ready pod pi-test --timeout=60s

kubectl exec pi-test -- aws sts get-caller-identity
kubectl exec pi-test -- aws s3 ls
```

기대: `Arn` 이 `assumed-role/PodIdentityS3Reader/<session>`.

> **Pod Identity의 환경변수** (IRSA와 다름):
> ```bash
> kubectl exec pi-test -- env | grep AWS
> ```
> ```
> AWS_CONTAINER_CREDENTIALS_FULL_URI=http://169.254.170.23/v1/credentials
> AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE=/var/run/secrets/pods.eks.amazonaws.com/serviceaccount/eks-pod-identity-token
> ```
> SDK는 이 URL에서 자격증명 받음 (Agent가 응답).

## 5. SA annotation 비교

```bash
kubectl get sa pod-identity-sa -o yaml | yq '.metadata.annotations'
# IRSA의 eks.amazonaws.com/role-arn 어노테이션이 없음!
```

→ Pod Identity 는 SA 어노테이션이 아니라 **EKS Pod Identity Association** 이라는 별도 리소스로 매핑.

## 6. 같은 Role 을 다른 SA 에도 연결

```bash
kubectl create sa another-sa -n kube-system

aws eks create-pod-identity-association \
  --cluster-name eks-study \
  --namespace kube-system \
  --service-account another-sa \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/PodIdentityS3Reader

aws eks list-pod-identity-associations --cluster-name eks-study \
  --query 'associations[].[namespace,serviceAccount,roleArn]' --output table
```

→ 같은 IAM Role 이 두 SA 에 매핑됨. **IRSA 였다면** Trust Policy 의 sub 조건을 두 개로 늘려야 했을 것.

> **운영 시나리오**: dev/staging/prod 클러스터가 같은 IAM Role을 공유하는 패턴이 자연스러워짐.
> IRSA였다면 클러스터별 Trust 정책 관리해야 했음.

## 7. 정리

```bash
kubectl delete -f /tmp/pi-pod.yaml
kubectl delete sa pod-identity-sa
kubectl delete sa another-sa -n kube-system

# Association 삭제
for assoc in $(aws eks list-pod-identity-associations --cluster-name eks-study \
  --query 'associations[].associationId' --output text); do
  aws eks delete-pod-identity-association --cluster-name eks-study --association-id $assoc
done

aws iam detach-role-policy --role-name PodIdentityS3Reader \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam delete-role --role-name PodIdentityS3Reader
```

## IRSA vs Pod Identity 정리

| | IRSA | Pod Identity |
|---|---|---|
| Trust 정책 | OIDC issuer + SA sub 박아야 함 | `pods.eks.amazonaws.com` 만 |
| Role 재사용 | 각 SA 마다 sub 추가 | Association 만 추가 |
| 새 클러스터 | OIDC issuer 다르므로 Trust 정책 추가 | 같은 Role 재사용 |
| 의존성 | OIDC provider | `eks-pod-identity-agent` addon |
| 출시 | 2019 | 2023말 |
| 생태계 | 거의 모든 도구 지원 | 일부 SDK 버전 필요 |

> 신규 프로젝트라면 **Pod Identity** 권장. 기존 IRSA 도 잘 동작하므로 굳이 마이그레이션할 필요는 없음.

## 학습 확인 질문

1. Pod Identity 의 IAM Role 재사용성이 IRSA 보다 좋은 이유는?
2. Pod Identity 가 동작하려면 클러스터에 어떤 컴포넌트가 떠 있어야 하나?
3. 같은 클러스터에서 IRSA 와 Pod Identity 를 동시 사용 가능한가?

> **힌트**:
> 1. Trust Policy가 클러스터 OIDC URL을 박지 않으므로 같은 Role을 여러 클러스터/여러 SA에 재사용 가능. 매핑은 별도 PodIdentityAssociation API.
> 2. `eks-pod-identity-agent` addon (DaemonSet). 노드별 1개씩 떠서 자격증명 프록시 역할.
> 3. 가능. 둘은 독립적. Pod의 SA 설정에 따라 어느 쪽이 동작할지 결정 (둘 다 어노테이션/association이 있으면 Pod Identity 우선).

다음: [quiz.md](./quiz.md)
