# 흔한 함정 5선 — 09. MSA 배포

## 1. ImagePull 실패 — ECR 권한

**증상**: `Failed to pull image "...dkr.ecr...": no basic auth credentials`.

**원인**: 노드 IAM Role 에 `AmazonEC2ContainerRegistryReadOnly` 누락.

**해결**:
```bash
NODE_ROLE=$(aws eks describe-nodegroup --cluster-name eks-study --nodegroup-name workers \
  --query 'nodegroup.nodeRole' --output text | awk -F/ '{print $NF}')
aws iam attach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# 노드 재시작 또는 Pod 삭제 후 재기동
kubectl delete pod -n order --all
```

---

## 2. ALB Target 이 unhealthy

**증상**: ALB DNS로 호출 시 502/503.

**원인 후보**:
- target-type: ip 인데 Pod 의 9090 포트는 readiness, ALB health check 는 80 으로 보냄 → 다른 포트
- alb.ingress 의 healthcheck-path 가 앱에 없음 (`/health` vs `/healthz`)
- Pod 자체 readinessProbe 실패

**진단**:
```bash
# Target Group 의 health 상태
TG_ARN=$(aws elbv2 describe-target-groups \
  --query 'TargetGroups[?starts_with(TargetGroupName,`k8s-order`)].TargetGroupArn|[0]' --output text)
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# Pod 직접 health check
kubectl exec -n order deploy/order-service -- wget -qO- localhost:8080/healthz
```

**해결**: 어노테이션으로 health check 경로/포트 명시:
```yaml
alb.ingress.kubernetes.io/healthcheck-path: /healthz
alb.ingress.kubernetes.io/healthcheck-port: traffic-port    # Service의 targetPort 사용
```

---

## 3. gRPC 호출이 hang 또는 connection refused

**증상**: order-service 가 user-service:50051 에 호출 → timeout.

**원인 후보**:
- Service 의 port 정의가 잘못됨 (50051 이 아닌 다른 값)
- Pod 의 readinessProbe 가 실패해 Endpoints 에 등록 안 됨
- gRPC 클라이언트가 plain text 가 아니라 TLS 시도 (서버는 plaintext)

**진단**:
```bash
kubectl get endpoints -n order user-service
kubectl exec -n order deploy/order-service -- nc -zv user-service 50051
```

---

## 4. 매니페스트의 ACCOUNT_ID 치환 누락

**증상**: Pod의 image 가 `ACCOUNT_ID.dkr.ecr...` 그대로. ImagePull 즉시 실패.

**원인**: 매니페스트의 자리표시자를 sed 로 치환 안 함.

**해결**: lab-01 의 sed 절차 재수행, 또는 Helm/Kustomize 사용 권장.

대안 — Kustomize:
```yaml
# kustomization.yaml
images:
  - name: ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/eks-study/order-service
    newName: 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/eks-study/order-service
    newTag: v1
```

---

## 5. 학습 끝났는데 ALB 가 안 사라짐

**증상**: `kubectl delete ns order` 실행 후 ALB 콘솔에 여전히 ALB 가 남음.

**원인**:
- group.name 어노테이션으로 다른 Ingress 도 같은 ALB 사용 중 → 마지막 Ingress 가 사라져야 ALB 삭제
- AWS LB Controller Pod 이 죽어서 조치 못 함

**진단**:
```bash
kubectl get ingress -A
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```

**해결**:
```bash
# 그래도 ALB가 남으면 직접 삭제
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?starts_with(LoadBalancerName,`k8s-`)]|[0].LoadBalancerArn' --output text)
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
```
