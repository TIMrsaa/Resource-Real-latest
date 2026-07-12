# Lab 02 — Access Entries: "동료에게 권한 주기" 실전

> 시나리오: 신입 동료(읽기 전용)와 배포 봇(특정 ns에 edit)에게 클러스터 접근을 줍니다. 실제 동료 대신 **IAM 역할 2개**를 만들어 연기합니다 — 끝나면 cleanup.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 0. 게스트 명단 현황

```bash
aws eks list-access-entries --cluster-name $CLUSTER --region $AWS_REGION
```

✅ 내(생성자) ARN과 노드 역할이 보입니다 — **"누가 들어올 수 있나"가 전부 조회되는 것** 자체가 구세대(aws-auth) 대비 진보입니다.

## Step 1. 연기용 IAM 역할 2개

```bash
cat > trust.json <<EOF
{ "Version": "2012-10-17", "Statement": [{ "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::$ACCOUNT_ID:root" },
  "Action": "sts:AssumeRole" }] }
EOF
aws iam create-role --role-name eks-newbie --assume-role-policy-document file://trust.json
aws iam create-role --role-name eks-deploy-bot --assume-role-policy-document file://trust.json
```

## Step 2. 신입: 클러스터 전체 읽기 전용 (AWS 정책 패턴)

```bash
aws eks create-access-entry --cluster-name $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/eks-newbie
aws eks associate-access-policy --cluster-name $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/eks-newbie \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=cluster
```

## Step 3. 배포 봇: shop ns 한정 edit (ns 스코프 패턴)

```bash
kubectl create ns shop 2>/dev/null || true
aws eks create-access-entry --cluster-name $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/eks-deploy-bot
aws eks associate-access-policy --cluster-name $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/eks-deploy-bot \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=shop
```

✅ **RBAC YAML 한 줄 없이** ns 한정 권한 — k8s 11에서 Role+RoleBinding으로 했던 일의 EKS 네이티브판. (커스텀이 필요하면 kubernetesGroups + 직접 만든 RBAC — theory §4의 정밀 패턴)

## Step 4. 검증 — 역할로 변신해서 쳐보기

```bash
# 신입으로 변신
CREDS=$(aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT_ID:role/eks-newbie \
  --role-session-name test --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
export AWS_ACCESS_KEY_ID=$(echo $CREDS | cut -d' ' -f1)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | cut -d' ' -f2)
export AWS_SESSION_TOKEN=$(echo $CREDS | cut -d' ' -f3)

kubectl auth whoami                              # arn:...:assumed-role/eks-newbie/...
kubectl get pods -A | head -3                    # ✅ 읽기 OK
kubectl create deployment x --image=nginx 2>&1 | tail -1   # ❌ Forbidden — view니까
kubectl delete ns shop 2>&1 | tail -1            # ❌ Forbidden

# 원래 나로 복귀
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

같은 방법으로 deploy-bot 검증 (핵심 두 줄):
```bash
# (assume-role을 eks-deploy-bot으로 반복 후)
kubectl create deployment web --image=public.ecr.aws/nginx/nginx:1.27 -n shop   # ✅ shop에선 edit
kubectl get pods -n default 2>&1 | tail -1                                       # ❌ 다른 ns는 Forbidden
# (복귀: unset ×3)
```

✅ **인증(IAM assume-role) → 매핑(access entry) → 인가(access policy의 스코프)** 의 전 경로를 두 인격으로 검증했습니다.

## Step 5. 감사 관점 마무리

```bash
aws eks list-access-entries --cluster-name $CLUSTER --region $AWS_REGION
for ARN in eks-newbie eks-deploy-bot; do
  aws eks list-associated-access-policies --cluster-name $CLUSTER --region $AWS_REGION \
    --principal-arn arn:aws:iam::$ACCOUNT_ID:role/$ARN \
    --query 'associatedAccessPolicies[].{policy:policyArn,scope:accessScope}' --output table
done
```

✅ "이 클러스터에 누가, 어떤 범위로" — 분기 보안 감사(k8s 33)의 EKS 항목이 이 두 명령입니다.

## 정리

```bash
bash cleanup.sh
```
