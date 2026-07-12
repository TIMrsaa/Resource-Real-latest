# Lab 01 — ClusterConfig로 EKS 클러스터 생성

## ⚠️ 비용 시작

이 lab부터 EKS Control Plane 비용($0.10/시간)이 발생합니다. Part 2 끝나면 반드시 클러스터 삭제.

> **💸 EKS 비용 구조 (한 번만 정리하면 영원히 안 잊음)**
> - **Control Plane**: $0.10/시간 = 24시간 켜두면 ~$72/월
> - **EC2 노드**: 인스턴스 타입별 시간 과금 (t3.medium ≈ $0.05/시간)
> - **NAT Gateway**: $0.045/시간 + 데이터 처리 비용
> - **EBS**: gp3 30GB ≈ $2.4/월 (노드당)
> - **Load Balancer**: NLB $0.022/시간, ALB $0.0225/시간 + LCU
>
> = 학습용 클러스터 24시간 켜두면 일주일에 $30 사라짐. 자기 전 `eksctl delete cluster` 습관!

## 학습 확인 포인트

- [ ] eksctl이 만드는 CloudFormation Stack을 봤다
- [ ] OIDC provider가 활성화됨을 확인했다
- [ ] kubectl로 노드/Pod에 접근 가능하다

> **🌱 이 lab 핵심 개념 미리보기**
> - **eksctl**: AWS가 만든 EKS 전용 CLI. YAML 1장 → CloudFormation → EKS 전체 생성
> - **CloudFormation (CFN)**: AWS의 IaC 서비스. JSON/YAML로 AWS 리소스 묶음을 "스택"으로 관리
> - **OIDC Provider**: 외부 신원 제공자(EKS의 ServiceAccount 등)를 IAM이 신뢰하게 하는 통로 (IRSA의 전제)
> - **Managed Node Group**: AWS가 관리(패치/AMI 갱신 보조)해주는 노드 묶음
> - **kubeconfig**: kubectl이 어느 클러스터에 어떻게 접속할지 적힌 설정 파일 (`~/.kube/config`)

## 1. (만약 Part 1 클러스터가 떠 있다면) 먼저 삭제

```bash
eksctl delete cluster --name eks-study --region ap-northeast-2 --wait
```

(이미 없다면 스킵)

> **삭제도 약 10~15분 소요**. CFN 스택을 역순으로 정리하기 때문.
> `--wait` 안 붙이면 비동기 (다른 작업 가능). 붙이면 끝까지 블로킹.

## 2. ClusterConfig 검토

```bash
cat manifests/cluster.yaml
```

핵심 포인트:
- `iam.withOIDC: true` — IRSA 활성화
- `vpc.nat.gateway: Single` — NAT Gateway 1개로 비용 절감
- `managedNodeGroups.spot: true` — Spot 인스턴스
- `addons` — vpc-cni, coredns, kube-proxy, ebs-csi 사전 설치

> **🧠 ClusterConfig 한 줄씩 풀어보기**
>
> **`iam.withOIDC: true`** 가 하는 일:
> 1. EKS 클러스터에 OIDC issuer URL 생성 (`https://oidc.eks.ap-northeast-2.amazonaws.com/id/...`)
> 2. 이 URL을 IAM의 "Identity Provider" 로 등록
> 3. 이후 IAM Role의 Trust Policy에 "이 OIDC + 특정 K8s SA만 허용" 조건 사용 가능 → **IRSA**
>
> **`vpc.nat.gateway: Single`**:
> NAT Gateway는 Private 서브넷의 Pod이 인터넷 호출(이미지 pull, AWS API 등)할 때 거치는 관문.
> - `Single`: 1개 AZ에만 배치 (~$32/월). 그 AZ 죽으면 다른 AZ Pod도 인터넷 못 씀
> - `HighlyAvailable`: AZ별 1개 (~$96/월). 운영 권장
> - `Disable`: NAT 없음. 노드 public 서브넷에 둘 때만 가능
>
> **`managedNodeGroups.spot: true`**:
> Spot = AWS 잉여 EC2 (~70% 할인). 단점: AWS가 2분 전 통보 후 회수 가능.
> 학습/내결함성 워크로드엔 OK. DB 같은 stateful은 위험.
>
> **`addons`**:
> AWS가 버전 호환성을 보장하는 부가 컴포넌트들.
> - `vpc-cni`: Pod에 VPC IP 할당 (Pod끼리 EC2처럼 통신)
> - `coredns`: 클러스터 내 DNS (svc 이름 → IP 변환)
> - `kube-proxy`: Service IP → Pod IP 라우팅 (iptables/ipvs 룰 관리)
> - `aws-ebs-csi-driver`: PV 동적 프로비저닝 (PVC → 자동 EBS 생성)

## 3. 클러스터 생성

```bash
eksctl create cluster -f manifests/cluster.yaml
```

소요 시간: **15 ~ 20분**.

> **이 시간 동안 무슨 일이 벌어지는가?**
> 1. CFN 스택 `eksctl-eks-study-cluster` 생성 → VPC, IAM, EKS Control Plane 만듦 (~10분)
> 2. CFN 스택 `eksctl-eks-study-addon-*` → addon들 설치 (~3분)
> 3. CFN 스택 `eksctl-eks-study-nodegroup-workers` → ASG + EC2 띄움 (~5분)
> 4. eksctl이 `~/.kube/config` 자동 업데이트 (kubectl 즉시 사용 가능)
>
> 커피 한 잔 ☕

별도 터미널에서 진행 상황 모니터:
```bash
watch -n10 'aws cloudformation list-stacks \
  --query "StackSummaries[?starts_with(StackName,\`eksctl-eks-study\`)].[StackName,StackStatus]" \
  --output table'
```

> **`watch -n10`**: 10초마다 명령 재실행. 진행 상황 실시간 확인용 (Linux/macOS).
> Windows에선 PowerShell의 `while ($true) { ...; Start-Sleep 10 }` 패턴.

```
StackName                              | StackStatus
eksctl-eks-study-cluster               | CREATE_IN_PROGRESS
eksctl-eks-study-addon-vpc-cni         | CREATE_IN_PROGRESS
eksctl-eks-study-nodegroup-workers     | CREATE_IN_PROGRESS
```

모두 `CREATE_COMPLETE` 가 되면 끝.

## 4. kubectl 접근 검증

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods -A
```

> **`kubectl config current-context`**: 현재 어느 클러스터에 연결됐나?
> 출력 예: `arn:aws:eks:ap-northeast-2:1234:cluster/eks-study`
> 여러 클러스터를 오갈 땐 `kubectl config use-context <name>` 으로 전환.
>
> **`-A` (=`--all-namespaces`)**: 모든 NS의 Pod 보기. 안 붙이면 default NS만.
> 시스템 Pod들은 `kube-system` NS에 살기 때문에 처음엔 -A가 필수.

기대:
```
NAME                                              STATUS   ROLES    AGE   VERSION
ip-10-20-x-x.ap-northeast-2.compute.internal     Ready    <none>   2m    v1.30.x
ip-10-20-y-y.ap-northeast-2.compute.internal     Ready    <none>   2m    v1.30.x

# 시스템 Pod (각 NS):
NAMESPACE     NAME
kube-system   aws-node-xxxxx          ← VPC CNI (DaemonSet)
kube-system   coredns-xxxxx
kube-system   ebs-csi-controller-xxx
kube-system   ebs-csi-node-xxxxx      ← DaemonSet
kube-system   kube-proxy-xxxxx        ← DaemonSet
```

> **🧠 DaemonSet 이란?**
> "모든 노드에 정확히 1개씩 띄우는 워크로드". 노드 추가되면 자동으로 거기에도 Pod 생성.
> - `aws-node` (CNI): 각 노드에서 Pod IP 할당 담당
> - `kube-proxy`: 각 노드의 라우팅 룰 관리
> - `ebs-csi-node`: 각 노드에서 EBS 마운트
>
> "노드별로 무조건 있어야 하는 시스템 컴포넌트" 패턴 = DaemonSet.

## 5. OIDC provider 확인 (IRSA의 전제)

```bash
aws eks describe-cluster --name eks-study --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text
```

기대 (URL 형식):
```
https://oidc.eks.ap-northeast-2.amazonaws.com/id/AAABBBCCC...
```

> **🧠 OIDC issuer URL 의 정체**
> "이 클러스터의 SA가 발급한 토큰을 검증할 수 있는 공개키 엔드포인트" 입니다.
> AWS IAM이 이 URL을 신뢰하게 등록 → SA 토큰을 가진 Pod이 IAM Role을 빌릴 수 있게 됨.
>
> 이 URL 끝의 `AAABBBCCC...` 가 OIDC Provider ID. IAM의 Identity Provider에 등록될 때 이 ID 사용.

IAM Identity Provider 등록 확인:
```bash
ISSUER_HOSTPATH=$(aws eks describe-cluster --name eks-study --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||')

aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, '${ISSUER_HOSTPATH}')]"
```

기대: 1개 결과 (Arn).

## 6. CFN Stack 살펴보기

```bash
aws cloudformation describe-stack-resources \
  --stack-name eksctl-eks-study-cluster \
  --query 'StackResources[].[ResourceType,LogicalResourceId,PhysicalResourceId]' \
  --output table | head -30
```

생성된 자원 종류:
- `AWS::EC2::VPC`, `Subnet`, `RouteTable`, `NatGateway`, `InternetGateway`
- `AWS::EKS::Cluster`
- `AWS::IAM::Role` (Cluster Role + Service Role)

> **🧠 왜 IAM Role이 두 개인가?**
> - **Cluster Role** (=Cluster Service Role): EKS 컨트롤 플레인이 AWS API를 호출할 때 (ELB 만들기, EC2 ENI 부착 등)
> - **Node Role**: EC2 노드 인스턴스가 AWS API를 호출할 때 (ECR pull, CloudWatch 로그 전송 등)
>
> 분리 이유: 최소 권한. Pod이 노드 IAM 빌리는 사고 시 영향 범위 최소화.

```bash
aws cloudformation describe-stack-resources \
  --stack-name eksctl-eks-study-nodegroup-workers \
  --query 'StackResources[].ResourceType' --output text
```

→ `AWS::EKS::Nodegroup` 등.

## 7. CloudWatch Logs 확인

ClusterConfig에서 `clusterLogging` 활성화했으므로:
```bash
aws logs describe-log-streams \
  --log-group-name /aws/eks/eks-study/cluster \
  --query 'logStreams[].logStreamName' --output text | head
```

```bash
aws logs tail /aws/eks/eks-study/cluster --follow --since 5m | head -20
```

→ kube-apiserver 등의 로그가 흐릅니다.

> **🧠 클러스터 로그 5종**
> - `api`: API Server 호출 로그 (가장 많음)
> - `audit`: 감사 로그 (누가/언제/무엇을 — 보안 감사 필수)
> - `authenticator`: IAM 인증 결과
> - `controllerManager`: 컨트롤 루프 실행 로그
> - `scheduler`: Pod 스케줄링 결정
>
> 활성화하면 CloudWatch에 저장 (인입량 만큼 과금). 학습용으론 7일 보관 권장.

## 8. (선택) Access Entry 추가

다른 IAM 사용자가 이 클러스터를 쓰게 하려면:
```bash
ARN=arn:aws:iam::123456789012:user/colleague
aws eks create-access-entry --cluster-name eks-study --principal-arn $ARN
aws eks associate-access-policy --cluster-name eks-study \
  --principal-arn $ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

> **🧠 Access Entry vs aws-auth ConfigMap**
> 예전엔 `kube-system/aws-auth` ConfigMap을 수정해 IAM 사용자를 K8s에 매핑했음 (실수 시 클러스터 락아웃 위험).
> EKS 1.23+ 부터 **Access Entry API** 도입 → AWS API로 안전하게 관리.
> 지금 만드는 클러스터는 새 방식이 기본.

## 학습 확인 질문

1. eksctl이 만드는 CFN Stack 중 클러스터 자체를 정의하는 stack의 이름은?
2. `iam.withOIDC: true` 가 만드는 AWS 자원은?
3. NAT Gateway를 `Single` 로 한 단점은?

> **힌트**:
> 1. `eksctl-<클러스터명>-cluster` (예: `eksctl-eks-study-cluster`)
> 2. EKS 클러스터의 OIDC issuer URL을 가리키는 IAM "Identity Provider" 객체
> 3. NAT Gateway가 있는 AZ 장애 시 다른 AZ의 Pod도 인터넷 못 씀 (단일 장애점)

다음: [lab-02-nodegroups.md](./lab-02-nodegroups.md)
