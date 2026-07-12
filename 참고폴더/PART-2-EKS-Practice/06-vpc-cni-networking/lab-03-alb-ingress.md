# Lab 03 — ALB Ingress 시연

## ⚠️ 비용

ALB가 만들어지면 시간당 약 0.0225 USD. 학습 끝나면 즉시 삭제.

## 학습 확인 포인트

- [ ] Ingress 리소스 적용만으로 ALB가 자동 생성됨을 봤다
- [ ] ALB Target Group에 Pod IP가 직접 등록됨을 확인했다 (IP target type)
- [ ] ALB DNS로 외부에서 접근 가능

> **🌱 핵심 개념 미리보기**
> - **ALB (Application Load Balancer)**: AWS의 L7 로드밸런서. HTTP/HTTPS 라우팅
> - **Target Group**: ALB가 트래픽을 분배할 백엔드 묶음 (EC2 또는 IP)
> - **Target Type IP vs Instance**: ALB가 Pod에 직접 가나, 노드를 거쳐 가나
> - **Ingress**: K8s의 L7 라우팅 규칙 객체 (실제 라우팅은 Ingress Controller가)

## 1. echo 앱 + Ingress 적용

```bash
kubectl apply -f manifests/echo-ingress.yaml
kubectl get deploy,svc,ingress
```

> **여기서 일어나는 일** (apply 한 순간 ~2분 동안):
> 1. K8s가 Deployment/Service/Ingress 객체 저장
> 2. AWS LBC가 Ingress 변화 감지 (watch)
> 3. LBC가 AWS API 호출 → ALB 생성 → Target Group 생성 → 리스너 등록
> 4. Pod이 Ready 되면 Pod IP를 Target Group에 등록
> 5. ALB Health Check 통과 → 트래픽 받기 시작

## 2. Ingress 상태 확인

```bash
kubectl get ingress echo --watch
```

처음에는 `ADDRESS` 가 비어있다가 약 1~2분 후 ALB DNS로 채워짐:
```
NAME   CLASS   HOSTS   ADDRESS                                                            PORTS
echo   alb     *       k8s-default-echo-xxxxxxxxxx.ap-northeast-2.elb.amazonaws.com       80
```

> **`ADDRESS` 가 빈 채로 안 채워질 때**:
> - LBC Pod 로그 확인 (`kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`)
> - 자주 보이는 원인: 서브넷 태그 누락 (`kubernetes.io/role/elb=1`), IAM 권한 부족, 잘못된 어노테이션

## 3. AWS 콘솔에서 ALB 확인

```bash
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Type==`application`].[LoadBalancerName,DNSName,State.Code]' \
  --output table
```

```bash
ALB_NAME=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Type==`application`]|[0].LoadBalancerName' \
  --output text)
echo "ALB: $ALB_NAME"

# Target Group 확인
TG_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(LoadBalancerArns[0], '$ALB_NAME')]|[0].TargetGroupArn" \
  --output text)
echo "TG: $TG_ARN"

# Targets (Pod IP가 직접 등록되어 있어야 함)
aws elbv2 describe-target-health --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State]' \
  --output table
```

기대:
```
+----------------+------+---------+
| 10.20.x.y      | 80   | healthy |
| 10.20.x.z      | 80   | healthy |
+----------------+------+---------+
```

→ `Target.Id` 가 Pod IP! Instance 모드라면 노드 IP였을 텐데, IP 모드라 직접.

> **🧠 Target Type 비교 (실무 매우 중요)**
>
> | 항목 | `instance` 모드 | `ip` 모드 |
> |------|----------------|----------|
> | Target Group에 등록되는 것 | EC2 노드 ID | Pod IP |
> | 트래픽 흐름 | ALB → 노드 NodePort → kube-proxy → Pod | ALB → Pod 직접 |
> | hop 수 | 2 (LB → node → pod) | 1 (LB → pod) |
> | Pod 변경 반영 | endpoints 변경 → kube-proxy iptables → 노드 죽으면 다시 | LBC가 즉시 Target Group 갱신 |
> | client IP 보존 | 어려움 (NodePort 거쳐서) | 가능 |
> | VPC IP 풀 사용 | 노드만 | Pod까지 (CNI가 IP 직접 부여 필수) |
>
> **EKS의 표준은 `ip` 모드** — VPC CNI가 Pod에 VPC IP 부여하므로 가능. 성능 + 정확성 우수.

## 4. 외부에서 호출

```bash
ALB_DNS=$(kubectl get ingress echo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB DNS: $ALB_DNS"

curl -s http://$ALB_DNS/ | jq .host       # echo-server는 요청 정보를 JSON 으로 반환
curl -s http://$ALB_DNS/foo/bar | jq '.path,.headers'
```

> **DNS 전파 시간**: ALB DNS가 응답하기까지 30~60초 더 필요할 수 있음.
> `nslookup $ALB_DNS` 가 IP 반환할 때까지 대기.

## 5. path 라우팅 시연

매니페스트 수정:
```bash
cat > /tmp/echo-paths.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: study
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: echoserver
                port: { number: 80 }
          - path: /
            pathType: Prefix
            backend:
              service:
                name: echoserver
                port: { number: 80 }
EOF

kubectl apply -f /tmp/echo-paths.yaml

# 재호출
curl -s http://$ALB_DNS/api/orders | jq .path
curl -s http://$ALB_DNS/health | jq .path
```

> **🧠 `alb.ingress.kubernetes.io/group.name: study` 가 핵심 (비용 절감)**
> 기본: Ingress 1개 = ALB 1개 (= 비용 ↑, ALB 한도 도달 위험)
> Group 사용: 같은 group.name 가진 Ingress들이 **하나의 ALB 공유**
>
> ```
>   group: study
>     ├─ Ingress: echo (path=/)
>     ├─ Ingress: api  (host=api.example.com)
>     └─ Ingress: web  (host=app.example.com)
>   → 위 세 Ingress가 ALB 1개에 통합 (~$0.022/시 1개 비용)
> ```
>
> 운영 권장 패턴: 도메인별/서비스별 Ingress 작성 + 같은 group으로 묶음.
>
> **pathType 종류**:
> - `Prefix` : `/api` 가 `/api`, `/api/`, `/api/orders` 다 매칭
> - `Exact`  : `/api` 만 정확히 매칭 (`/api/` 는 안됨)
> - `ImplementationSpecific`: 컨트롤러마다 다름 (ALB는 Prefix처럼 동작)

## 6. ALB 삭제 확인

```bash
kubectl delete -f manifests/echo-ingress.yaml
sleep 30

aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Type==`application`].LoadBalancerName' --output text
```

기대: 빈 결과 (또는 우리가 만든 게 없음).

> **ALB가 안 사라질 때 점검 순서**:
> 1. `kubectl get ingress -A` — 다른 Ingress가 같은 ALB를 group으로 공유 중일 수 있음
> 2. `kubectl get targetgroupbindings -A` — TargetGroupBinding이 남아있으면 ALB 유지
> 3. LBC Pod 로그에 삭제 시도 에러 (IAM 권한 등)
> 4. 수동 삭제 (학습 환경): `aws elbv2 delete-load-balancer --load-balancer-arn ...`

## 학습 확인 질문

1. `target-type: ip` vs `target-type: instance` 의 차이를 한 줄로?
2. `alb.ingress.kubernetes.io/group.name` 어노테이션의 효과는?
3. Ingress 리소스를 삭제했는데 ALB가 안 사라지면 무엇을 점검?

> **힌트**:
> 1. `ip`는 ALB가 Pod IP에 직접 트래픽 (1 hop). `instance`는 노드 NodePort 거쳐서 (2 hop).
> 2. 같은 그룹의 여러 Ingress가 하나의 ALB 공유 → 비용 절감 + 도메인 통합.
> 3. 다른 Ingress가 같은 group을 공유 중인지, TargetGroupBinding 남아있는지, LBC 로그에 IAM 에러 있는지.

다음: [quiz.md](./quiz.md)
