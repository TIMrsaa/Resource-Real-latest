# Lab 01 — Karpenter 설치

## 학습 확인 포인트

- [ ] Karpenter 공식 CFN 템플릿이 만드는 것을 봤다
- [ ] IRSA 로 Karpenter Controller 가 EC2 API 호출 가능
- [ ] Helm 으로 Karpenter Pod 가 떠 있다

> **🌱 Karpenter 가 뭐고 왜 쓰는가?**
> "Pending Pod이 생기면 가장 효율적인 EC2를 즉시 띄워주는" 차세대 노드 오토스케일러.
>
> **Cluster Autoscaler (CA) vs Karpenter**:
> | 항목 | CA (구버전) | Karpenter |
> |------|------------|----------|
> | 동작 | ASG의 desired 조절 | ASG 우회, EC2 API 직접 호출 |
> | 인스턴스 선택 | 미리 정의한 ASG 타입만 | Pod 요구사항 보고 600+ 타입 중 최적 선택 |
> | 노드 추가 속도 | ~3분 | ~30~60초 |
> | Spot 회수 처리 | 단순 | 자동 마이그레이션 |
> | 다중 인스턴스 타입 | ASG별 1개 (제한) | NodePool 1개에 N개 가능 |
>
> 실무 EKS는 거의 모두 Karpenter 도입 중.

## 1. 환경 변수

```bash
export CLUSTER_NAME=eks-study
export AWS_REGION=ap-northeast-2
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export KARPENTER_VERSION="1.0.6"     # 본 lab 시점 stable
```

> **`export`**: 현재 셸 + 자식 프로세스에서 사용 가능한 환경변수.
> 다음 단계의 `${CLUSTER_NAME}` 같은 표기는 셸이 자동 치환.

## 2. 공식 CFN 템플릿으로 IAM/SQS 셋업

```bash
TEMP=$(mktemp)
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > $TEMP

aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file $TEMP \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}" \
  --region ${AWS_REGION}
```

> **🧠 `CAPABILITY_NAMED_IAM` 이란?**
> CFN이 IAM 리소스를 만들 때 명시적 동의 필요 (보안 안전장치). 이름 박힌 Role 만들 거라 NAMED 버전.
> 없으면: `Requires capabilities : [CAPABILITY_NAMED_IAM]` 에러.

이 CFN Stack 이 만드는 것:
- `KarpenterNodeRole-eks-study` — 노드용 IAM Role
- `KarpenterControllerRole-eks-study` — Controller IRSA용
- `KarpenterInterruptionQueue-eks-study` — Spot Interruption SQS
- EventBridge Rules (EC2 Spot, Health, Rebalance → SQS)

> **🧠 IAM Role 이 두 개인 이유 (Controller vs Node)**
> | Role | 누가 사용? | 권한 |
> |------|----------|------|
> | **ControllerRole** | Karpenter Pod (IRSA) | EC2 인스턴스 RunInstances/Terminate, IAM PassRole, SQS receive 등 |
> | **NodeRole** | Karpenter가 만든 EC2 노드 | EKS 노드 표준 (ECR pull, kubelet 등) |
>
> Controller가 노드를 만들면 → 그 노드는 NodeRole을 부여받음 → 노드가 클러스터 join.
>
> **🧠 Spot Interruption SQS 의 역할**
> AWS가 Spot 회수 2분 전 통보 → EventBridge가 SQS에 메시지 → Karpenter가 SQS 폴링 → 그 노드를 cordon + drain → 새 노드 미리 띄움.
> = 사용자 트래픽 무중단 Spot 회수 처리.

## 3. Karpenter NodeRole 을 클러스터 aws-auth 에 추가 (또는 Access Entries)

노드가 join 하려면 클러스터의 RBAC 등록 필요.

> **🧠 왜 IAM Role을 K8s에 등록해야 하는가?**
> EC2 인스턴스가 부팅되며 kubelet이 EKS API에 "join 시켜줘" 요청.
> EKS는 그 요청의 IAM principal을 확인 → "이 IAM이 K8s 사용자/그룹으로 매핑되어 있나?" 검증.
> 매핑 없으면 거부 → 노드가 NotReady 상태로 빠짐.
>
> 매핑 방법 두 가지: Access Entry API (신) vs aws-auth ConfigMap (구).

**Access Entries 사용** (EKS 1.30+ 권장):
```bash
aws eks create-access-entry \
  --cluster-name ${CLUSTER_NAME} \
  --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --type EC2_LINUX \
  --region ${AWS_REGION}
```

> **`--type EC2_LINUX`**: 노드용 사전 정의 권한 세트. system:bootstrappers + system:nodes 그룹 자동 부여.

또는 **aws-auth ConfigMap** 사용:
```bash
eksctl create iamidentitymapping --cluster ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --username "system:node:{{EC2PrivateDNSName}}" \
  --group system:bootstrappers \
  --group system:nodes
```

## 4. 서브넷 / 보안그룹 태깅

Karpenter 가 어느 서브넷 / SG 를 쓸지 알도록 태그:

```bash
# 서브넷 (private)
SUBNETS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
aws ec2 create-tags --resources $SUBNETS \
  --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}"

# 클러스터 보안그룹
CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 create-tags --resources $CLUSTER_SG \
  --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}"
```

> **🧠 `karpenter.sh/discovery` 태그의 의미**
> Karpenter EC2NodeClass의 `subnetSelectorTerms`/`securityGroupSelectorTerms` 가 이 태그로 자동 검색.
> ```yaml
> subnetSelectorTerms:
>   - tags:
>       karpenter.sh/discovery: eks-study   # ← 매칭
> ```
> 태그 없으면? → "no subnets found" 에러로 노드 생성 실패.
> 여러 클러스터 한 VPC에 있으면 클러스터 이름 값으로 분리 가능.

## 5. Helm 설치

```bash
helm registry logout public.ecr.aws 2>/dev/null

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace karpenter --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=Karpenter-${CLUSTER_NAME}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}" \
  --set "controller.resources.requests.cpu=100m" \
  --set "controller.resources.requests.memory=512Mi" \
  --set "controller.resources.limits.memory=1Gi" \
  --wait
```

> **🧠 옵션 풀이**
> - `oci://public.ecr.aws/karpenter/karpenter`: AWS ECR Public의 OCI 레지스트리. HTTPS HelmRepo와 다른 OCI 형식
> - `helm registry logout`: 익명 pull을 위해 기존 인증 제거
> - `--upgrade --install`: 없으면 install, 있으면 upgrade (idempotent)
> - `\\.` 이스케이프: 어노테이션 키 `eks.amazonaws.com/role-arn` 의 점(.)을 Helm set이 경로 구분자로 해석 안 하게
> - `--wait`: Pod 다 Ready 될 때까지 명령 블로킹

## 6. 검증

```bash
kubectl get pods -n karpenter
kubectl get crd | grep karpenter
```

기대:
```
NAME                          READY   STATUS    RESTARTS   AGE
karpenter-xxx-aaa             1/1     Running   0          2m
karpenter-xxx-bbb             1/1     Running   0          2m

ec2nodeclasses.karpenter.k8s.aws
nodeclaims.karpenter.sh
nodepools.karpenter.sh
```

> **🧠 CRD 3종 의미**
> | CRD | 역할 |
> |-----|------|
> | `NodePool` | "어떤 노드를 만들 수 있나" 제약 (인스턴스 타입, 한도, 라벨/taint) |
> | `EC2NodeClass` | "AWS 측 설정" (AMI, 서브넷, SG, 디스크) |
> | `NodeClaim` | "이 Pod 위해 노드 1개 만들어줘" 라는 요청 객체 (Karpenter가 만들고 관리) |
>
> 사용자가 만드는 건 NodePool/EC2NodeClass. NodeClaim은 Karpenter가 알아서 생성.

## 7. Controller 로그

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20
```

기대 (대략):
```
INFO  starting controller manager
INFO  webhook server ...
INFO  starting reconciler  for: nodepool.karpenter.sh
INFO  spot interruption queue ready  queue=Karpenter-eks-study
```

## 학습 확인 질문

1. CFN 템플릿이 만드는 IAM Role 두 개의 차이는 (Controller vs Node)?
2. Karpenter 가 만든 노드가 클러스터에 join 하려면 어떤 권한이 필요한가?
3. `karpenter.sh/discovery` 태그를 안 붙이면 어떻게 되는가?

> **힌트**:
> 1. ControllerRole = Karpenter Pod(IRSA)이 EC2 만들/SQS 읽을 권한. NodeRole = 만들어진 EC2가 클러스터 join 후 ECR/kubelet 동작할 권한.
> 2. Access Entry 또는 aws-auth ConfigMap에 NodeRole이 system:nodes/system:bootstrappers 그룹으로 매핑돼야.
> 3. EC2NodeClass의 subnet/SG selector가 매칭 실패 → NodeClaim 생성 시 "no subnets found" 에러 → Pod Pending 유지.

다음: [lab-02-first-nodepool.md](./lab-02-first-nodepool.md)
