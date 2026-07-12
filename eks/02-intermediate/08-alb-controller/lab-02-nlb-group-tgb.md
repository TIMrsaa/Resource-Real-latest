# Lab 02 — ALB 통합(group.name), NLB, TargetGroupBinding

## Step 1. 두 번째 서비스 — 그리고 ALB 통합

비교를 위해 먼저 상황: 서비스가 늘 때마다 Ingress를 만들면 ALB도 늡니다(비용). `group.name`으로 합쳐봅시다:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: web
  labels: { app: api }
spec:
  replicas: 2
  selector:
    matchLabels: { app: api }
  template:
    metadata:
      labels: { app: api }
    spec:
      containers:
        - name: agnhost
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          command: ["/agnhost", "netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: web
spec:
  selector: { app: api }
  ports:
    - port: 80
      targetPort: 8080
EOF

# 기존 shop Ingress와 새 api Ingress 둘 다 같은 그룹으로
kubectl annotate ingress shop -n web alb.ingress.kubernetes.io/group.name=shared-web --overwrite
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  namespace: web
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: shared-web
    alb.ingress.kubernetes.io/group.order: "20"
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /api
        pathType: Prefix
        backend: { service: { name: api, port: { number: 80 } } }
EOF
sleep 60
kubectl get ingress -n web    # 두 Ingress의 ADDRESS가 같습니다!
```

```bash
aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query 'length(LoadBalancers[?Type==`application`])'
ALB_DNS=$(kubectl get ingress api -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$ALB_DNS/hostname; echo          # shop으로
curl -s http://$ALB_DNS/api/hostname; echo      # api로 (경로 규칙)
```

✅ **Ingress 2개, ALB 1개** — 같은 ALB의 리스너 규칙으로 합쳐졌습니다(group.order가 우선순위). 서비스 20개면 ALB 20→1, 월 수백 달러의 차이. 단 그룹 = 설정 공유 운명체라는 점(theory §4)도 기억.

## Step 2. NLB — L4의 실물

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: shop-nlb
  namespace: web
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
spec:
  type: LoadBalancer
  selector: { app: shop }
  ports: [{ port: 80, targetPort: 8080 }]
EOF
kubectl get svc shop-nlb -n web -w    # EXTERNAL-IP에 NLB DNS (~2-3분)
```

```bash
NLB_DNS=$(kubectl get svc shop-nlb -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$NLB_DNS/hostname; echo
```

✅ 같은 백엔드를 L4(NLB)로도 노출 — 선택 기준(theory §5): HTTP 라우팅/리다이렉트가 필요한가(ALB) vs 순수 TCP 성능/고정 IP인가(NLB). 14에서 이 NLB로 성능 특성을 측정합니다.

## Step 3. TargetGroupBinding — "LB는 남의 것, 연결만 내가"

인프라팀이 만든 LB라고 가정하고, 대상그룹만 직접 만들어 연기:

```bash
VPC_ID=$(aws eks describe-cluster --name k8s-study --region ap-northeast-2 \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)
TG_ARN=$(aws elbv2 create-target-group --region ap-northeast-2 \
  --name manual-shop-tg --protocol HTTP --port 8080 --vpc-id $VPC_ID \
  --target-type ip --health-check-path /healthz \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

cat <<EOF | kubectl apply -f -
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata: { name: shop-tgb, namespace: web }
spec:
  serviceRef: { name: shop, port: 80 }
  targetGroupARN: $TG_ARN
EOF
sleep 20
aws elbv2 describe-target-health --target-group-arn $TG_ARN --region ap-northeast-2 \
  --query 'TargetHealthDescriptions[].Target.Id'
```

✅ **컨트롤러가 그 대상그룹에 Pod IP를 등록**했습니다 — LB/리스너는 없어도(인프라팀 몫이라 가정) 연결 고리는 K8s가 관리. Terraform(LB) ↔ K8s(Pod)의 표준 경계 인터페이스.

## Step 4. 운영 결정표 (산출물)

```markdown
# LB 전략 (우리 클러스터)
- 기본: ALB Ingress + target-type: ip + group.name=<도메인 묶음>
- 거버넌스: group 공유 시 어노테이션 제한(admission — k8s 23) 검토
- L4/고성능/고정IP: NLB (14에서 튜닝)
- 인프라팀 소유 LB: TargetGroupBinding으로 접속
- 비용 점검: ALB 수 = group 수인지 월 1회 확인 (모듈 01 lab-02 루틴에 추가)
```

## 정리 (★ 과금 차단)

```bash
bash cleanup.sh
```
