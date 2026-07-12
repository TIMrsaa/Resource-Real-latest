# Lab 01 — 설정 파일, CloudFormation, 인증 경로 해부

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
mkdir -p ~/eks-lab && cd ~/eks-lab
```

## Step 1. 기존 클러스터를 설정 파일로 역추출

```bash
# 현 클러스터의 모습을 ClusterConfig 초안으로 (완전 자동은 아니지만 골격 확인용)
eksctl get cluster --name $CLUSTER --region $AWS_REGION -o yaml
eksctl get nodegroup --cluster $CLUSTER --region $AWS_REGION -o yaml
```

theory §1의 ClusterConfig를 `cluster.yaml`로 작성해보세요 — 위 출력의 실제 값(버전, 노드 타입)을 반영해서. **이 파일이 DR의 시작점**입니다(eks 24): 클러스터가 사라져도 이 파일이 있으면 같은 모양으로 재생성.

```bash
# 문법 검증 (만들지는 않습니다)
eksctl create cluster -f cluster.yaml --dry-run | head -30
```

✅ dry-run 출력 = eksctl이 채워 넣은 기본값까지 보이는 **완전한 선언** — 이걸 Git에 커밋하는 것이 정석.

## Step 2. 뒷면 확인 — CloudFormation 스택

```bash
aws cloudformation list-stacks --region $AWS_REGION \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[?contains(StackName,`eksctl`)].StackName'
# 스택 하나의 산출물 들여다보기
aws cloudformation describe-stack-resources --region $AWS_REGION \
  --stack-name eksctl-$CLUSTER-cluster \
  --query 'StackResources[].{type:ResourceType,id:LogicalResourceId}' --output table | head -25
```

✅ VPC, 서브넷, SG, IAM 역할, 클러스터 — eksctl 한 줄이 만든 실물 목록. **"eksctl이 안 끝나요/실패해요"의 진단처가 이 스택의 이벤트 탭**이라는 것을 기억하세요:

```bash
aws cloudformation describe-stack-events --region $AWS_REGION \
  --stack-name eksctl-$CLUSTER-cluster --query 'StackEvents[0:5].{status:ResourceStatus,reason:ResourceStatusReason}' --output table
```

## Step 3. kubeconfig 해부 — 비밀이 없습니다

```bash
kubectl config view --minify -o jsonpath='{.users[0].user.exec}' | python3 -m json.tool
```

예상:
```json
{ "command": "aws", "args": ["eks", "get-token", "--cluster-name", "k8s-study", ...] }
```

✅ 비밀번호/인증서 대신 **exec 한 줄** — kubectl이 매 요청 전에 AWS CLI를 불러 토큰을 받습니다.

## Step 4. get-token 직접 — 토큰의 실체

```bash
aws eks get-token --cluster-name $CLUSTER --region $AWS_REGION | python3 -m json.tool | head -8
# 토큰 수명 확인
aws eks get-token --cluster-name $CLUSTER --region $AWS_REGION \
  --query 'status.expirationTimestamp' --output text; date -u +%Y-%m-%dT%H:%M:%SZ
```

✅ `k8s-aws-v1.` 으로 시작하는 토큰 = **서명된 STS 질의의 포장**이고, 만료가 ~14분 뒤입니다. 이 토큰으로 API 서버에 직접 쳐보면:

```bash
TOKEN=$(aws eks get-token --cluster-name $CLUSTER --region $AWS_REGION --query 'status.token' --output text)
ENDPOINT=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.endpoint' --output text)
curl -sk -H "Authorization: Bearer $TOKEN" $ENDPOINT/api/v1/namespaces/default/pods?limit=1 | head -8
```

✅ kubectl 없이 curl로 EKS API 서버 호출 성공 — k8s 21(요청의 일생)의 ①인증 단계가 "STS 보증"으로 치환된 것을 직접 확인했습니다.

## Step 5. 나는 누구로 들어와 있나

```bash
kubectl auth whoami
```

예상:
```
Username: arn:aws:iam::...:role/... (또는 user/...)
Groups:   [system:authenticated ...]
```

✅ K8s가 보는 내 정체 = **IAM ARN 그대로** — access entry가 매핑한 결과입니다. 다음 lab에서 이 명단을 직접 관리합니다.

## 정리

`cluster.yaml`은 보존(이 파트 내내 진화시킵니다). 만든 리소스 없음.
