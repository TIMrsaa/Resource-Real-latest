# Lab 01 — IRSA를 손으로: 배선부터 토큰 해부까지

> eksctl의 한 줄(`create iamserviceaccount`)이 해주는 일을 **일부러 수동으로** — 그래야 고장났을 때 어디를 보는지 압니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl create ns iam-lab
```

## Step 1. 배선 ① — OIDC 공급자 등록 (클러스터당 1회)

```bash
ISSUER=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.identity.oidc.issuer' --output text)
echo $ISSUER
# eksctl로 등록 (이미 있으면 무시됨)
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER --region $AWS_REGION --approve
aws iam list-open-id-connect-providers
```

✅ eks 02에서 "존재만 확인"한 issuer가 IAM에 **공증 기관**으로 등록됐습니다 — AWS가 이 클러스터의 토큰 서명을 검증할 수 있게 된 것.

## Step 2. 배선 ② — 역할 + 신뢰 정책 (정밀 조준)

```bash
OIDC_ID=$(echo $ISSUER | sed 's|https://||')
cat > trust-irsa.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/$OIDC_ID" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": { "StringEquals": {
      "$OIDC_ID:sub": "system:serviceaccount:iam-lab:s3-reader",
      "$OIDC_ID:aud": "sts.amazonaws.com"
    }}
  }]
}
EOF
aws iam create-role --role-name irsa-s3-reader --assume-role-policy-document file://trust-irsa.json
aws iam attach-role-policy --role-name irsa-s3-reader \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

✅ Condition의 `sub` — **iam-lab ns의 s3-reader SA만** 이 역할을 쓸 수 있습니다. 이 줄의 오타가 IRSA 고장 원인 1위(pitfall).

## Step 3. 배선 ③ — SA 어노테이션, 그리고 Pod

```bash
kubectl create sa s3-reader -n iam-lab
kubectl annotate sa s3-reader -n iam-lab \
  eks.amazonaws.com/role-arn=arn:aws:iam::$ACCOUNT_ID:role/irsa-s3-reader

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: awscli
  namespace: iam-lab
  labels: { run: awscli }
spec:
  serviceAccountName: s3-reader          # ← IRSA 어노테이션이 붙은 SA
  containers:
    - name: awscli
      image: public.ecr.aws/aws-cli/aws-cli:latest
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/awscli -n iam-lab --timeout=120s
```

## Step 4. 주입의 증거 — webhook이 꽂은 것들

```bash
kubectl exec awscli -n iam-lab -- env | grep AWS_
```

예상:
```
AWS_ROLE_ARN=arn:aws:iam::...:role/irsa-s3-reader
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

✅ 우리는 이 변수를 설정한 적 없습니다 — **EKS의 mutating webhook**(k8s 23)이 SA 어노테이션을 보고 주입했습니다. 볼륨도:

```bash
kubectl get pod awscli -n iam-lab -o jsonpath='{.spec.volumes}' | python3 -m json.tool | grep -B2 -A6 "aws-iam-token"
```

→ `projected` 토큰, `audience: sts.amazonaws.com`, 만료 86400s — **k8s 11에서 배운 바로 그 projected SA 토큰**입니다.

## Step 5. 토큰 해부 — JWT 열어보기

```bash
kubectl exec awscli -n iam-lab -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token \
  | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
```

예상 (발췌):
```json
{
  "aud": ["sts.amazonaws.com"],
  "iss": "https://oidc.eks.ap-northeast-2.amazonaws.com/id/...",
  "sub": "system:serviceaccount:iam-lab:s3-reader",
  "exp": ...
}
```

✅ **신뢰 정책의 Condition과 1:1 대응** — iss(공증 기관), sub(누구), aud(용도). STS는 이 셋과 서명을 검증합니다. "마법"의 전체가 평문으로 드러났습니다.

## Step 6. 작동 확인 — 나는 누구인가

```bash
kubectl exec awscli -n iam-lab -- aws sts get-caller-identity
# → "Arn": "...assumed-role/irsa-s3-reader/..."  ★
kubectl exec awscli -n iam-lab -- aws s3 ls | head -3        # 허용된 일
kubectl exec awscli -n iam-lab -- aws ec2 describe-instances --region $AWS_REGION 2>&1 | tail -1   # 거부!
```

✅ S3 읽기는 되고 EC2는 AccessDenied — **이 Pod만, 이 권한만.** 최소 권한의 완성. 같은 노드의 다른 Pod은 이 역할과 무관합니다(검증하고 싶으면 기본 SA Pod에서 caller-identity — 노드 역할이 나온다 = 폴백의 실체도 확인).

## 정리

리소스는 lab-02에서 비교용으로 유지.
