# eksctl 치트시트

> 02에서 배운 선언(ClusterConfig)이 원본, CLI 플래그는 그 축약입니다. 실무는 **YAML을 git에** — 그것이 24의 DR 자산이 됩니다.

## 클러스터

```bash
# 선언에서 생성 (권장 — 재현 가능)
eksctl create cluster -f cluster.yaml

# 조회
eksctl get cluster --region ap-northeast-2
eksctl utils describe-stacks --cluster k8s-study --region ap-northeast-2   # CloudFormation 실체

# kubeconfig 갱신 (인증은 get-token → STS — 02)
aws eks update-kubeconfig --name k8s-study --region ap-northeast-2

# 삭제 (순서: 워크로드 LB/PVC 먼저! — 고아 리소스 방지, 22)
eksctl delete cluster --name k8s-study --region ap-northeast-2
```

## 노드그룹 (05, 21)

```bash
eksctl create nodegroup --cluster k8s-study --name workers \
  --node-type m6i.large --nodes 2 --nodes-min 2 --nodes-max 6 \
  --node-ami-family AmazonLinux2023

eksctl get nodegroup --cluster k8s-study --region ap-northeast-2
eksctl scale nodegroup --cluster k8s-study --name workers --nodes 4

# 업그레이드 (21 — drain 자동, PDB 존중)
eksctl upgrade nodegroup --cluster k8s-study --name workers --kubernetes-version 1.37

# Blue/Green: 새 NG 생성 → drain → 구 NG 삭제 (21 lab-02)
eksctl delete nodegroup --cluster k8s-study --name blue --drain --wait
```

## 권한 — Pod Identity / IRSA (09)

```bash
# Pod Identity (신형 — 권장)
eksctl create podidentityassociation --cluster k8s-study --region ap-northeast-2 \
  --namespace app --service-account-name app-sa \
  --permission-policy-arns arn:aws:iam::<acct>:policy/AppPolicy

eksctl get podidentityassociation --cluster k8s-study --namespace app

# IRSA (구형 — OIDC 기반)
eksctl utils associate-iam-oidc-provider --cluster k8s-study --approve
eksctl create iamserviceaccount --cluster k8s-study --namespace app --name app-sa \
  --attach-policy-arn arn:aws:iam::<acct>:policy/AppPolicy --approve
```

## 액세스 (02)

```bash
# access entry — aws-auth ConfigMap의 후계
eksctl create accessentry --cluster k8s-study \
  --principal-arn arn:aws:iam::<acct>:role/Developer \
  --access-policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope namespace=team-a

eksctl get accessentry --cluster k8s-study
```

## 애드온 (11)

```bash
eksctl get addon --cluster k8s-study
eksctl create addon --cluster k8s-study --name vpc-cni --version latest  # ⚠️ latest 금물, default 사용
eksctl update addon --cluster k8s-study --name coredns --version v1.11.4-eksbuild.2
```

## ClusterConfig 골격 (02·05·11)

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: k8s-study
  region: ap-northeast-2
  version: "1.36"
iam:
  podIdentityAssociations:                    # 09
    - namespace: app
      serviceAccountName: app-sa
      permissionPolicyARNs: ["arn:aws:iam::<acct>:policy/AppPolicy"]
addons:                                        # 11 — configuration-values가 진실의 원천
  - name: vpc-cni
    configurationValues: '{"env":{"ENABLE_PREFIX_DELEGATION":"true"}}'
  - name: coredns
  - name: kube-proxy
managedNodeGroups:                             # 05
  - name: workers
    instanceType: m6i.large
    minSize: 2
    maxSize: 6
    amiFamily: AmazonLinux2023
    updateConfig: { maxUnavailable: 1 }        # 21 — 교체 폭
```

## 자주 쓰는 조합

```bash
# 업그레이드 preflight (21 lab-01)
aws eks list-insights --cluster-name k8s-study --filter categories=UPGRADE_READINESS
kubectl get pdb -A            # disruptionsAllowed=0 색출

# 삭제 전 고아 방지 (22)
kubectl delete ingress --all -A       # ALB 회수
kubectl delete pvc --all -A           # EBS 회수
```
