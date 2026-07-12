# Lab 02 — Pod Identity: 단순화의 실측과 마이그레이션

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. 에이전트 확인 (애드온)

```bash
aws eks describe-addon --cluster-name $CLUSTER --addon-name eks-pod-identity-agent \
  --region $AWS_REGION --query 'addon.status' 2>/dev/null \
  || aws eks create-addon --cluster-name $CLUSTER --addon-name eks-pod-identity-agent --region $AWS_REGION
kubectl get ds eks-pod-identity-agent -n kube-system
```

✅ 노드마다 에이전트(DaemonSet) — Pod의 자격증명 요청을 받아 eks-auth API로 교환해주는 "상주 직원".

## Step 2. 역할 — 신뢰 정책이 이렇게 단순해집니다

```bash
cat > trust-pi.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "pods.eks.amazonaws.com" },
    "Action": ["sts:AssumeRole", "sts:TagSession"]
  }]
}
EOF
aws iam create-role --role-name pi-s3-reader --assume-role-policy-document file://trust-pi.json
aws iam attach-role-policy --role-name pi-s3-reader \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

✅ lab-01 Step 2와 비교하세요: OIDC ARN도, 클러스터별 sub 조건도 없습니다 — **모든 클러스터에서 재사용 가능한 고정 문구.** IRSA의 "클러스터×SA마다 신뢰 정책" 지옥이 사라진 지점.

## Step 3. association — 매핑은 EKS API 객체로

```bash
kubectl create sa s3-reader-pi -n iam-lab
aws eks create-pod-identity-association --cluster-name $CLUSTER --region $AWS_REGION \
  --namespace iam-lab --service-account s3-reader-pi \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/pi-s3-reader
aws eks list-pod-identity-associations --cluster-name $CLUSTER --region $AWS_REGION
```

✅ SA에는 **어노테이션조차 없습니다** — 매핑이 K8s 밖(EKS API)에 있어 감사/IaC가 깔끔하고, "누가 어떤 역할을 받나"를 AWS 쪽에서 전수 조회할 수 있습니다 (access entries와 같은 사상 — eks 02).

## Step 4. 작동 + 배선 차이 관찰

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: awscli-pi
  namespace: iam-lab
  labels: { run: awscli-pi }
spec:
  serviceAccountName: s3-reader-pi       # ← Pod Identity association 대상 SA
  containers:
    - name: awscli-pi
      image: public.ecr.aws/aws-cli/aws-cli:latest
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/awscli-pi -n iam-lab --timeout=120s

kubectl exec awscli-pi -n iam-lab -- env | grep AWS_
```

예상:
```
AWS_CONTAINER_CREDENTIALS_FULL_URI=http://169.254.170.23/v1/credentials
AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE=/var/run/secrets/pods.eks.amazonaws.com/serviceaccount/eks-pod-identity-token
```

✅ IRSA의 `AWS_ROLE_ARN/WEB_IDENTITY` 대신 **컨테이너 자격증명 URI** — SDK 체인의 다른 칸에 걸립니다(theory §3). 동작 확인:

```bash
kubectl exec awscli-pi -n iam-lab -- aws sts get-caller-identity
# → assumed-role/pi-s3-reader/...
kubectl exec awscli-pi -n iam-lab -- aws s3 ls | head -3
```

## Step 5. 세션 태그 보너스 — 정책에서 클러스터/ns 조건

```bash
# Pod Identity는 세션에 자동 태그: eks-cluster-name, kubernetes-namespace 등
# 역할 정책에서 이렇게 쓸 수 있습니다 (개념 확인):
cat <<'EOF'
"Condition": { "StringEquals": { "aws:PrincipalTag/kubernetes-namespace": "iam-lab" } }
EOF
```

✅ 하나의 역할을 여러 ns가 공유하되 **태그 조건으로 리소스를 분리**하는 패턴이 열립니다 — IRSA에선 어렵던 것.

## Step 6. 비교표 완성 + 마이그레이션 절차 (산출물)

```markdown
# IRSA vs Pod Identity — 실측 후 결론
| | IRSA | Pod Identity |
|---|---|---|
| 배선 수 | OIDC 등록+신뢰정책(클러스터·SA별)+어노테이션 | 에이전트(1회)+고정 신뢰정책+association |
| 주입물 | ROLE_ARN + 토큰 파일 | 자격증명 URI + 토큰 |
| 멀티클러스터 | 신뢰정책 수정 누적 | association 추가만 |
| 선택 | 비EKS/기존 환경 | ★ 신규 기본

# IRSA → PI 마이그레이션 (워크로드별)
1. 역할 신뢰 정책에 pods.eks.amazonaws.com 문구 추가 (IRSA 문구와 병존 가능)
2. association 생성 (같은 ns/SA)
3. Pod 재기동 → env가 URI 방식인지 + caller-identity 확인
4. 안정 후 SA 어노테이션 제거 (→ 전 클러스터 완료 시 OIDC 조건 제거)
순서의 핵심: 병존시켜 검증 후 옛 경로 제거 — 빅뱅 금지
```

## 정리

```bash
bash cleanup.sh
```
