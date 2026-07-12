# Lab 01 — 설치, 첫 NodePool, 그리고 "왜 이 타입?"

Karpenter를 공유 클러스터에 설치하고, Pending Pod가 **수십 초 만에 노드가 되는** 장면을 시계로 잽니다. 그리고 그 노드가 왜 그 타입인지 — 계산의 근거를 라벨에서 읽습니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export KARPENTER_VERSION=1.5.0     # 작성 시점 기준 — 최신 확인: karpenter.sh
```

## Step 1. IAM 뼈대 — 공식 CloudFormation 한 장

노드 역할·컨트롤러 정책·인터럽션 큐(SQS)를 공식 템플릿이 한 번에 만듭니다:

```bash
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/docs/getting-started/getting-started-with-karpenter/cloudformation.yaml" \
  -o karpenter-cfn.yaml
aws cloudformation deploy --region $AWS_REGION \
  --stack-name Karpenter-$CLUSTER --template-file karpenter-cfn.yaml \
  --capabilities CAPABILITY_NAMED_IAM --parameter-overrides ClusterName=$CLUSTER
```

산출물 3종: `KarpenterNodeRole-k8s-study`(노드가 쓸 역할), `KarpenterControllerPolicy-k8s-study`(컨트롤러 권한), `Karpenter-k8s-study` SQS 큐(spot 2분 경고 수신 — theory §5).

## Step 2. 컨트롤러 권한 배선 (09·12의 그 패턴)

```bash
cat > kp-trust.json <<'EOF'
{ "Version": "2012-10-17", "Statement": [{
  "Effect": "Allow", "Principal": { "Service": "pods.eks.amazonaws.com" },
  "Action": ["sts:AssumeRole","sts:TagSession"] }]}
EOF
aws iam create-role --role-name KarpenterControllerRole-$CLUSTER \
  --assume-role-policy-document file://kp-trust.json 2>/dev/null || true
aws iam attach-role-policy --role-name KarpenterControllerRole-$CLUSTER \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/KarpenterControllerPolicy-$CLUSTER
eksctl create podidentityassociation --cluster $CLUSTER --region $AWS_REGION \
  --namespace karpenter --service-account-name karpenter \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/KarpenterControllerRole-$CLUSTER 2>/dev/null || true
```

새 노드가 클러스터에 **조인할 자격**도 필요합니다 — access entry(02에서 배운 그 문):

```bash
eksctl create accessentry --cluster $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/KarpenterNodeRole-$CLUSTER \
  --type EC2_LINUX 2>/dev/null || true
```

## Step 3. 발견 태그 — "어디에 노드를 지어도 되나"

EC2NodeClass의 selector가 찾을 표식을 서브넷·SG에 답니다:

```bash
SUBNETS=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
SG=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 create-tags --region $AWS_REGION --resources $SUBNETS $SG \
  --tags Key=karpenter.sh/discovery,Value=$CLUSTER
```

## Step 4. 컨트롤러 설치

```bash
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version $KARPENTER_VERSION --namespace karpenter --create-namespace \
  --set settings.clusterName=$CLUSTER \
  --set settings.interruptionQueue=Karpenter-$CLUSTER \
  --set serviceAccount.name=karpenter
kubectl rollout status deploy/karpenter -n karpenter --timeout=180s
```

## Step 5. 규칙서 — NodePool + EC2NodeClass

실험 격리를 위해 **taint를 단 풀**로 (34의 격리 문법이 여기서 재등장 — 우리 실험 Pod만 이 풀을 씁니다):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata: { name: default }
spec:
  amiSelectorTerms: [{ alias: al2023@latest }]
  role: KarpenterNodeRole-$CLUSTER
  subnetSelectorTerms: [{ tags: { karpenter.sh/discovery: $CLUSTER } }]
  securityGroupSelectorTerms: [{ tags: { karpenter.sh/discovery: $CLUSTER } }]
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata: { name: lab }
spec:
  template:
    spec:
      requirements:                       # 네거티브 설계 — 배제만 (theory §3)
      - { key: karpenter.k8s.aws/instance-category, operator: In, values: [c, m, r] }
      - { key: karpenter.k8s.aws/instance-generation, operator: Gt, values: ["4"] }
      - { key: kubernetes.io/arch, operator: In, values: [amd64] }
      - { key: karpenter.sh/capacity-type, operator: In, values: [on-demand] }
      taints: [{ key: lab, value: karpenter, effect: NoSchedule }]   # 실험 격리
      nodeClassRef: { group: karpenter.k8s.aws, kind: EC2NodeClass, name: default }
      expireAfter: 720h
  limits: { cpu: "8" }                    # ★ 안전핀 — 이 랩의 청구서 상한
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
EOF
kubectl get nodepool,ec2nodeclass       # READY: True 확인
```

## Step 6. 발화 — Pending이 노드가 되는 시간을 재라

```bash
# 요구가 명확한 워크로드 (1 vCPU × N)
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: inflate }
spec:
  replicas: 0
  selector: { matchLabels: { app: inflate } }
  template:
    metadata: { labels: { app: inflate } }
    spec:
      tolerations: [{ key: lab, value: karpenter, effect: NoSchedule }]
      nodeSelector: { karpenter.sh/nodepool: lab }
      containers:
      - name: pause
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.10
        resources: { requests: { cpu: "1" } }
EOF

date +%T; kubectl scale deploy inflate --replicas=4
kubectl get nodeclaims -w        # 몇 초 만에 NodeClaim 생성 → 등록 → Ready
```

다른 터미널에서:

```bash
kubectl get pods -l app=inflate -w      # Pending → Running까지의 총 시간을 기록 (~1분 내외)
```

✅ ASG 없이 노드가 태어났습니다 — **NodeClaim이라는 CRD가 그 생애의 장부**입니다(theory §2-⑤).

## Step 7. 해부 — "왜 이 타입인가"를 라벨에서 읽기

```bash
kubectl get nodeclaims -o wide     # 인스턴스 타입, 존, capacity-type
NODE=$(kubectl get nodes -l karpenter.sh/nodepool=lab -o jsonpath='{.items[0].metadata.name}')
kubectl get node $NODE -o json | python3 -c "
import json,sys
l=json.load(sys.stdin)['metadata']['labels']
for k in sorted(l):
    if 'karpenter' in k or 'instance' in k: print(f'{k} = {l[k]}')"
```

읽는 법: 4 Pod × 1 vCPU + DaemonSet 오버헤드 ≈ 5~6 vCPU → **8 vCPU급 (2xlarge) 1대**가 낙찰됐을 것입니다 — c/m/r 중 그 시점 가장 싼 것으로. 검산:

```bash
kubectl describe nodeclaim | grep -A5 "Events" | head -10    # launched → registered → initialized
kubectl get pods -l app=inflate -o wide                       # 전부 그 한 대에 bin-packing
```

✅ **타입을 우리가 고르지 않았습니다** — 규칙서(c/m/r, 5세대+) 안에서 계산이 골랐습니다. 이것이 04 Auto Mode가 숨기고 있던 그 동작의 원형입니다.

## 정리

inflate와 노드는 lab-02(consolidation)의 재료 — 그대로 둡니다. 여기서 중단하면 `bash cleanup.sh`.
