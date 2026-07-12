# Lab 01 — 설치, 첫 ALB, 실물 해부

> ⚠️ 이 lab부터 ALB 과금 시작 — lab-02까지 이어서 하고 cleanup으로 종료 권장.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. 컨트롤러 권한 (Pod Identity — 원리는 09에서)

```bash
# 공식 IAM 정책 다운로드 & 생성
curl -sLO https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy --policy-name ALBControllerPolicy --policy-document file://iam_policy.json 2>/dev/null || true

eksctl create podidentityassociation --cluster $CLUSTER --region $AWS_REGION \
  --namespace kube-system --service-account-name aws-load-balancer-controller \
  --permission-policy-arns arn:aws:iam::$ACCOUNT_ID:policy/ALBControllerPolicy
```

## Step 2. Helm 설치 (k8s 17의 그 도구)

```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER \
  --set serviceAccount.name=aws-load-balancer-controller
kubectl rollout status deploy/aws-load-balancer-controller -n kube-system
kubectl get ingressclass    # alb 클래스 등장!
```

## Step 3. 앱 + Ingress — 선언 한 장

```bash
kubectl create ns web
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  namespace: web
  labels: { app: shop }
spec:
  replicas: 3
  selector:
    matchLabels: { app: shop }
  template:
    metadata:
      labels: { app: shop }
    spec:
      containers:
        - name: agnhost
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          command: ["/agnhost", "netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: shop
  namespace: web
spec:
  selector: { app: shop }
  ports:
    - port: 80
      targetPort: 8080
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: web
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: shop, port: { number: 80 } } }
EOF

# ALB 생성 관찰 (~2-3분)
kubectl get ingress shop -n web -w    # ADDRESS에 ALB DNS가 차오릅니다
```

```bash
ALB_DNS=$(kubectl get ingress shop -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$ALB_DNS/hostname; echo    # Pod 이름 응답!
```

✅ **Ingress YAML 한 장 → 인터넷에서 접근되는 ALB.** k8s 06에서 nginx로 하던 일이 AWS 실물로.

## Step 4. 실물 해부 — 컨트롤러가 만든 것들

```bash
# ALB
aws elbv2 describe-load-balancers --region $AWS_REGION \
  --query 'LoadBalancers[?contains(DNSName,`'$(echo $ALB_DNS | cut -d. -f1 | rev | cut -d- -f2- | rev)'`)].{arn:LoadBalancerArn,scheme:Scheme}' 2>/dev/null \
  || aws elbv2 describe-load-balancers --region $AWS_REGION --query 'LoadBalancers[].{name:LoadBalancerName,dns:DNSName}' --output table

# 대상그룹 — Pod IP가 직접 등록돼 있습니다!
TG=$(aws elbv2 describe-target-groups --region $AWS_REGION \
  --query 'TargetGroups[?contains(TargetGroupName,`k8s-web-shop`)].TargetGroupArn' --output text | head -1)
aws elbv2 describe-target-health --target-group-arn $TG --region $AWS_REGION \
  --query 'TargetHealthDescriptions[].{ip:Target.Id,port:Target.Port,state:TargetHealth.State}' --output table
kubectl get pods -n web -o wide    # Pod IP와 대조 — 일치!
```

✅ **대상그룹의 타겟 = Pod IP 그 자체** (ip 모드) — 노드를 거치지 않습니다. 07의 "Pod IP는 진짜 VPC IP"가 만든 직통 경로.

## Step 5. EndpointSlice 연동 검증 — readiness가 곧 등록

터미널 1: `watch -n3 "aws elbv2 describe-target-health --target-group-arn $TG --region $AWS_REGION --query 'TargetHealthDescriptions[].{ip:Target.Id,state:TargetHealth.State}' --output table"`

터미널 2:
```bash
kubectl scale deployment shop -n web --replicas=5    # 늘리면 타겟 추가
# 하나를 의도적으로 NotReady로 (k8s 38 #5의 그 수법)
kubectl patch deployment shop -n web -p '{"spec":{"template":{"spec":{"containers":[{"name":"agnhost","readinessProbe":{"httpGet":{"path":"/nope","port":8080}}}]}}}}'
```

✅ 새 Pod들이 타겟에 추가됐다가 → readiness 실패 버전이 뜨면 **draining→제거** — EndpointSlice를 따라가는 컨트롤러의 reconcile을 실측했습니다. k8s 14(readiness)가 ALB 트래픽 단절의 마지막 안전핀이라는 뜻.

```bash
# 원복
kubectl patch deployment shop -n web --type=json -p='[{"op":"remove","path":"/spec/template/spec/containers/0/readinessProbe"}]'
kubectl scale deployment shop -n web --replicas=3
```

## Step 6. "콘솔 수정은 되돌려진다" 검증 (선택, 빠름)

콘솔에서 그 ALB의 리스너 규칙 하나를 삭제해보세요 → 수십 초 내 컨트롤러가 재생성(컨트롤러 로그에 reconcile 기록). **진실은 K8s 객체**라는 원칙의 실연.

## 정리

리소스는 lab-02에서 계속 사용 — 끝까지 가면 cleanup.sh.
