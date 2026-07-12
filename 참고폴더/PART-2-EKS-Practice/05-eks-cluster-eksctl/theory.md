# 이론 — EKS 아키텍처

> **🌱 EKS = "엔진 정비는 AWS 가, 운전은 내가"**
> 비행기에 비유하면 *Control Plane (조종실/엔진)* 은 AWS 가 정비/패치/이중화, *Data Plane (객실/승객)* 은 내가 관리.
> 그래서 "왜 etcd 백업 안 해도 되지?" — AWS 가 해주기 때문. 대신 노드 OS 패치/Pod 운영은 100% 내 몫이다.

## 1. 책임 분담: AWS vs 사용자

```
┌─ AWS 책임 ─────────────────────────────┐
│  Control Plane                          │
│  ├─ kube-apiserver                      │
│  ├─ etcd                                │
│  ├─ scheduler                           │
│  ├─ controller-manager                  │
│  └─ (멀티 AZ 자동 복제, 패치, 백업)      │
└─────────────────────────────────────────┘
              │ (HTTPS API endpoint)
              ▼
┌─ 사용자 책임 ───────────────────────────┐
│  Data Plane                             │
│  ├─ Worker Nodes (EC2 또는 Fargate)      │
│  ├─ kubelet, kube-proxy, container rt   │
│  ├─ 워크로드 (Pod, Deployment, ...)       │
│  ├─ Networking (VPC, SG, IAM)           │
│  └─ Add-on (CNI, CSI, Ingress, ...)      │
└─────────────────────────────────────────┘
```

- **Control Plane**: AWS가 운영. 비용 시간당 약 $0.10. 직접 SSH 접근 불가, 로그는 CloudWatch로.
- **Data Plane**: 사용자가 운영. 노드를 직접 관리하거나 (Self-managed) AWS가 더 도와주는 모드 (Managed Node Group, Fargate) 선택.

> **🧠 "Control Plane 비용 = 클러스터 보유세"**
> Pod 가 0개여도 시간당 $0.10 (월 ~$73) 은 무조건 청구된다 — Control Plane 은 켜 있으면 비용 발생.
> 학습용 클러스터는 "쓸 때만 만들고 끝나면 삭제" 가 비용 절감의 핵심.

## 2. 노드 옵션 3가지

### 2.1 Managed Node Group

- AWS가 EC2 Auto Scaling Group을 관리
- 업데이트, 종료, 교체 자동화
- 학습/실무 기본 선택

### 2.2 Self-managed

- 직접 ASG 관리 → 더 큰 자유도 (커스텀 AMI, 특수 인스턴스 타입)
- 운영 부담 큼

### 2.3 Fargate

- 노드 개념 자체 없음. Pod 단위 서버리스
- VPC, 시간당 비용 모델
- Cold start, 일부 기능 제한 (DaemonSet 불가, GPU 불가)
- Karpenter 학습 목적이면 부적합

→ **본 커리큘럼은 Managed Node Group + Spot 사용.**

> **🧠 "Managed = AWS 가 OS 패치, Self = 내가 패치"**
> Self-managed 의 자유도는 매력적이지만 노드 OS CVE 가 뜰 때마다 본인이 AMI 빌드/롤아웃해야 한다.
> 학습/일반 운영은 무조건 Managed Node Group → 나중에 GPU 같은 특수 케이스에서만 Self-managed.

## 3. eksctl 의 역할

eksctl 명령 1번이 내부적으로 만드는 것:
- **CloudFormation Stack 여러 개**:
  - `eksctl-<cluster>-cluster` — VPC, IAM Role(Cluster), EKS Cluster 자체
  - `eksctl-<cluster>-nodegroup-<name>` — 노드 그룹 ASG, IAM Role
- **Kubeconfig 자동 갱신** (`~/.kube/config`)
- **OIDC provider** (옵션) — IRSA용
- **addon** 설치 (옵션)

CFN 콘솔에서 직접 보기:
```bash
aws cloudformation list-stacks \
  --query 'StackSummaries[?starts_with(StackName,`eksctl-eks-study`)].[StackName,StackStatus]' \
  --output table
```

> **🧠 "eksctl 은 CFN 의 wrapper" — 디버깅은 CFN 콘솔에서**
> eksctl 명령이 멈추거나 실패하면 *원인은 CloudFormation Stack Events* 에 있다.
> `eksctl create cluster` 가 영문 모르게 죽으면 → CFN 콘솔 → 해당 스택 → Events 탭에서 진짜 에러 메시지를 본다.

## 4. ClusterConfig YAML

명령어 옵션 대신 YAML로 클러스터 정의 — 재현성, 코드화.

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: eks-study
  region: ap-northeast-2
  version: "1.35"

iam:
  withOIDC: true        # IRSA 위해 필수

managedNodeGroups:
  - name: workers
    instanceType: t3.medium
    spot: true
    desiredCapacity: 2
    minSize: 0
    maxSize: 10
    volumeType: gp3
    iam:
      withAddonPolicies:
        ebs: true
        cloudWatch: true

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver
```

> **🧠 ClusterConfig 는 코드 — git 으로 관리하라**
> 콘솔 클릭으로 만든 클러스터는 *재현 불가능* (다음번에 똑같이 만들 자신이 없다).
> ClusterConfig YAML 을 레포에 두고 변경 추적하면, 클러스터 자체가 PR review 대상이 된다.

## 5. EKS 버전 정책

- 신규 마이너 버전이 약 분기마다 출시
- 각 버전은 **약 14개월 지원** (Standard) → 만료되기 전 업그레이드
- 학습용은 항상 최신 또는 N-1 권장 (2026-05 기준 1.35 또는 1.34)

```bash
eksctl utils describe-addon-versions --kubernetes-version 1.35
```

> **🧠 "최신만 좇지 말고, N-1 이 안전 지대"**
> 새 마이너 버전은 출시 직후 *addon 호환성 이슈* 가 종종 있다 — 1~2달 늦게 따라가는 게 안정적.
> Standard support 14개월 안에만 들어가면 충분히 안전.

## 6. 인증 (Auth) — IAM ↔ K8s RBAC

K8s 자체에는 IAM 사용자/역할 개념이 없습니다. EKS는 다음 두 메커니즘 중 하나:

### 6.1 aws-auth ConfigMap (Legacy)

`kube-system/aws-auth` ConfigMap에 IAM ARN을 K8s user/group 으로 매핑.
```yaml
mapUsers: |
  - userarn: arn:aws:iam::xxx:user/devops
    username: devops
    groups:
      - system:masters
```

### 6.2 EKS Access Entries (신규, 2024+)

```bash
aws eks create-access-entry \
  --cluster-name eks-study \
  --principal-arn arn:aws:iam::xxx:user/devops \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name eks-study \
  --principal-arn arn:aws:iam::xxx:user/devops \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

→ ConfigMap 편집 안 해도 됨, IAM 정책처럼 관리.

본 커리큘럼은 Access Entries 권장.

> **🧠 aws-auth ConfigMap 의 잘못된 편집 = 클러스터 락아웃 1위 사고**
> 한 줄 YAML 오타로 *모든 사람이 클러스터 접근 불가* 가 된다 (자기 자신 포함).
> Access Entries 는 IAM API 로 관리되어 *콘솔에서 복구 가능* — 동일 사고 시 락아웃되지 않는 게 큰 장점.

다음: [lab-01-create-cluster.md](./lab-01-create-cluster.md)
