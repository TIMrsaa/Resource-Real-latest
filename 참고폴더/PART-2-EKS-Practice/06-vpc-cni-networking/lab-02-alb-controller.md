# Lab 02 — AWS Load Balancer Controller 설치

## 학습 확인 포인트

- [ ] IAM Policy → IAM Role → ServiceAccount (IRSA) 흐름을 직접 만들어봤다
- [ ] Helm 으로 컨트롤러 설치 + values 설정
- [ ] 컨트롤러 Pod이 Ready 됨

> **🌱 이 lab의 핵심: AWS Load Balancer Controller (LBC)**
> Ingress/Service(LoadBalancer) 리소스를 감지해 → ALB/NLB 자동 생성하는 컨트롤러.
> 클러스터에 설치된 Pod 형태로 동작 (kube-system NS).
>
> **왜 이게 따로 있어야 하나?**
> EKS 기본 Cloud Controller Manager(CCM)도 LB는 만들 수 있지만 한계:
> - CCM: NLB만 (Service type=LoadBalancer)
> - LBC: ALB(Ingress) + NLB(Service) 둘 다, 어노테이션으로 풍부한 옵션
>
> 실무 EKS는 거의 모두 LBC 사용.

## 1. IAM Policy 다운로드 + 생성

```bash
curl -o /tmp/iam_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/iam_policy.json \
  --query 'Policy.Arn' --output text
```

기대: `arn:aws:iam::123456789012:policy/AWSLoadBalancerControllerIAMPolicy`

이미 있으면 에러 (그대로 진행 OK).

> **🧠 이 IAM Policy가 뭐 하는 건가?**
> LBC가 AWS API를 호출해 ALB/NLB를 만들고, Target Group을 관리하고, ENI를 부착하고...
> 이런 동작에 필요한 모든 IAM 권한 (~50개 액션) 묶음.
> AWS가 정확한 정책을 [공식 GitHub](https://github.com/kubernetes-sigs/aws-load-balancer-controller)에서 제공.
>
> **수동으로 작성하지 말 것**: 누락 시 LBC가 실패함. 공식 정책 그대로 쓰는 게 정석.

## 2. IRSA로 SA + IAM Role 한 번에

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve \
  --region=ap-northeast-2
```

이 명령이 한 번에:
- IAM Role 생성 (Trust 정책: 클러스터 OIDC를 신뢰)
- K8s ServiceAccount 생성 (`kube-system/aws-load-balancer-controller`)
- SA 의 annotation `eks.amazonaws.com/role-arn` 자동 설정

> **🧠 IRSA (IAM Roles for Service Accounts) 풀이**
>
> "Pod이 AWS API를 부를 때 어떤 IAM Role 권한으로?" 라는 문제의 해법.
>
> **옛날 방식**: 노드 IAM Role에 권한 부여 → 그 노드의 모든 Pod이 그 권한 사용 가능 (위험!)
> ```
>   Node IAM Role: SQS:* + S3:* + EBS:*
>     ├─ Pod A (SQS만 필요한데도 S3 다 보임)
>     ├─ Pod B (S3만 필요한데도 SQS 다 보임)  ← 권한 과잉
>     └─ ...
> ```
>
> **IRSA 방식**: 각 Pod의 SA마다 IAM Role 매핑 → 최소 권한
> ```
>   SA-A → IAM Role A (SQS만)  →  Pod A
>   SA-B → IAM Role B (S3만)   →  Pod B
> ```
>
> **동작 원리**:
> 1. K8s가 Pod에 SA 토큰을 자동 마운트 (JWT)
> 2. AWS SDK가 그 토큰을 STS에 전달 (`AssumeRoleWithWebIdentity`)
> 3. STS가 OIDC issuer 검증 → 임시 자격증명 발급
> 4. Pod이 그 자격증명으로 AWS API 호출

검증:
```bash
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml | yq '.metadata.annotations'
```

> **`yq`**: jq의 YAML 버전. macOS: `brew install yq`. 없으면 `... -o jsonpath='{.metadata.annotations}'` 로 대체.

## 3. Helm 으로 컨트롤러 설치

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-study \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 \
  --set vpcId=$(aws eks describe-cluster --name eks-study --query 'cluster.resourcesVpcConfig.vpcId' --output text)
```

> **🧠 각 옵션 의미**
> | 옵션 | 의미 |
> |------|------|
> | `clusterName` | LBC가 자기 클러스터 식별 (다른 클러스터 LB 안 건드리도록) |
> | `serviceAccount.create=false` | Helm이 SA 만들지 마라. 위에서 IRSA로 이미 만든 SA 사용 |
> | `serviceAccount.name` | 그 SA 이름 |
> | `region` | API 호출 리전 |
> | `vpcId` | LB 만들 VPC. 어노테이션 미지정 시 기본값 |
>
> **왜 SA를 따로 만들었는가?**
> Helm 차트가 SA를 만들면 IRSA 어노테이션 주입이 까다로움.
> → SA를 IRSA로 미리 만들고, Helm에는 "기존 SA 사용" 지시. 운영에서 흔한 패턴.

## 4. 검증

```bash
kubectl wait --for=condition=available --timeout=120s \
  deploy/aws-load-balancer-controller -n kube-system

kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

> **`kubectl wait`**: 특정 조건이 될 때까지 블로킹. CI/CD 파이프라인에서 유용.
> `condition=available` = Deployment가 ReadyReplicas == replicas 도달.

기대:
```
NAME                                            READY   STATUS    RESTARTS   AGE
aws-load-balancer-controller-xxxxx-aaaaa        1/1     Running   0          30s
aws-load-balancer-controller-xxxxx-bbbbb        1/1     Running   0          30s
```

> **🧠 왜 Pod이 2개?**
> 기본 replicas=2 (HA). 하지만 두 Pod이 동시에 동작하면 충돌(같은 ALB 두 번 생성 등)이라
> **leader election** 으로 1개만 활성, 1개는 standby (= leader 죽으면 즉시 인계).
>
> 로그에 `successfully acquired lease` 가 leader, 다른 Pod은 lease 대기 중.

로그 확인:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20
```

기대: `successfully acquired lease`, `Starting Controller` 등의 로그.

## 5. CRD 확인

```bash
kubectl get crd | grep elbv2
```

기대:
```
ingressclassparams.elbv2.k8s.aws
targetgroupbindings.elbv2.k8s.aws
```

> **🧠 CRD (Custom Resource Definition) 란?**
> K8s의 기본 객체(Pod, Service 등) 외에 사용자/Operator가 추가하는 객체 타입.
> LBC가 두 개 추가:
> - `IngressClassParams`: ALB 글로벌 설정 (Ingress들이 공유)
> - `TargetGroupBinding`: K8s Service ↔ ALB Target Group 직접 매핑 (Ingress 없이도 가능)

## 6. IngressClass 생성

```bash
cat > /tmp/ingressclass.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: ingress.k8s.aws/alb
EOF
kubectl apply -f /tmp/ingressclass.yaml

kubectl get ingressclass
```

이제 Ingress 리소스에 `ingressClassName: alb` 또는 기본값으로 ALB 자동 생성.

> **🧠 IngressClass 란?**
> "어떤 Ingress Controller가 이 Ingress 처리할지" 명시.
> 한 클러스터에 여러 Ingress Controller (예: NGINX + ALB) 설치 가능 → IngressClass로 분리.
> ```
>   Ingress (className: alb)   → AWS LBC가 ALB 만듦
>   Ingress (className: nginx) → NGINX Ingress Controller가 처리
> ```
>
> **`is-default-class: "true"`**: Ingress가 className 안 적으면 이 클래스 사용. 1개 클래스만 default 가능.

## 학습 확인 질문

1. IRSA 가 ServiceAccount 의 annotation 으로 `eks.amazonaws.com/role-arn` 만 설정했는데, 어떻게 IAM 권한이 작동하는가?
2. `serviceAccount.create=false` 옵션을 준 이유는?
3. 컨트롤러 Pod이 2개 떠 있는 이유는? (HA?)

> **힌트**:
> 1. EKS의 mutating webhook이 Pod 생성 시 자동으로 SA 토큰 + AWS_ROLE_ARN 환경변수 주입. SDK가 자동으로 STS AssumeRoleWithWebIdentity 호출.
> 2. eksctl로 IRSA 어노테이션이 미리 부착된 SA를 만들었기 때문에. Helm이 또 만들면 충돌.
> 3. HA + Leader Election. 2개 떠있어도 1개만 active(=leader), 다른 1개는 standby. leader 죽으면 즉시 인계.

다음: [lab-03-alb-ingress.md](./lab-03-alb-ingress.md)
