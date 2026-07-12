# eksctl 치트시트

## 클러스터 관리

```bash
# 최소 클러스터 (학습용)
eksctl create cluster \
  --name eks-study \
  --region ap-northeast-2 \
  --version 1.35 \
  --nodes 2 --node-type t3.medium \
  --managed --spot

# config 파일로 생성
eksctl create cluster -f cluster.yaml

# 목록
eksctl get cluster --region ap-northeast-2
eksctl get cluster --all-regions

# 삭제
eksctl delete cluster --name eks-study --region ap-northeast-2
```

## kubeconfig 등록

```bash
aws eks update-kubeconfig --name eks-study --region ap-northeast-2
# 또는
eksctl utils write-kubeconfig --cluster=eks-study --region=ap-northeast-2
```

## 노드 그룹

```bash
# 추가
eksctl create nodegroup \
  --cluster eks-study \
  --name spot-workers \
  --instance-types t3.medium,t3.large \
  --spot --nodes 2 --nodes-min 0 --nodes-max 10

# 목록
eksctl get nodegroup --cluster eks-study

# 스케일
eksctl scale nodegroup --cluster=eks-study --name=spot-workers --nodes=5

# 삭제
eksctl delete nodegroup --cluster=eks-study --name=spot-workers
```

## IAM / IRSA

```bash
# OIDC provider 연결
eksctl utils associate-iam-oidc-provider --cluster=eks-study --approve

# IRSA용 ServiceAccount + IAM Role 한 번에
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<acct>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve --override-existing-serviceaccounts

# 목록
eksctl get iamserviceaccount --cluster=eks-study
```

## EKS addon

```bash
# 목록 (사용 가능)
eksctl utils describe-addon-versions --kubernetes-version 1.35

# 설치
eksctl create addon \
  --name aws-ebs-csi-driver \
  --cluster eks-study \
  --service-account-role-arn arn:aws:iam::<acct>:role/<role>

# 설치된 목록
eksctl get addon --cluster eks-study

# 업그레이드
eksctl update addon --name vpc-cni --cluster eks-study --version v1.18.0-eksbuild.1

# 삭제
eksctl delete addon --name vpc-cni --cluster eks-study
```

## 클러스터 업그레이드

```bash
eksctl upgrade cluster --name=eks-study --version=1.31 --approve
eksctl upgrade nodegroup --name=spot-workers --cluster=eks-study
```

## 진단

```bash
eksctl utils describe-stacks --region=ap-northeast-2 --cluster=eks-study
eksctl utils describe-addon-configuration --name vpc-cni --version v1.18.0-eksbuild.1
```

## 클러스터 설정 파일 예시

```yaml
# cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: eks-study
  region: ap-northeast-2
  version: "1.35"

iam:
  withOIDC: true

managedNodeGroups:
  - name: workers
    instanceType: t3.medium
    spot: true
    desiredCapacity: 2
    minSize: 0
    maxSize: 10
    volumeType: gp3

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver
```

## 학습 비용 절감 팁

- 학습 끝나면 즉시 `eksctl delete cluster`
- 또는 `eksctl scale nodegroup ... --nodes=0` 으로 노드만 0
  (Control Plane 비용 $0.10/시간은 계속 부과되니 주의)
