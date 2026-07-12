# 흔한 함정 5선 — 06. VPC CNI & Networking

## 1. Pod 가 더 안 떠짐 — IP 부족

**증상**: `FailedScheduling: too many pods` 또는 `failed to assign an IP address`.

**원인**: 노드의 ENI 보조 IP 슬롯이 가득 참 (인스턴스 타입 한계).

**진단**:
```bash
kubectl describe node $NODE | grep -A2 'Capacity:\|Allocatable:'
# pods: 17 (t3.medium 기준)
```

**해결**:
- 더 큰 인스턴스 타입 사용 (m5.large = 29 Pod, m5.2xlarge = 58 Pod)
- Prefix Delegation 활성화 (`ENABLE_PREFIX_DELEGATION=true`)
- Karpenter (Part 3) 도입해 자동 노드 추가

---

## 2. VPC 서브넷 IP 고갈

**증상**: 새 Pod 가 안 뜨고 ENI 할당 실패. 노드 자체도 못 늘어남.

**원인**: VPC CNI 가 VPC 진짜 IP를 쓰므로 큰 클러스터에서 /24 (256 IP) 같은 작은 서브넷이 빠르게 소모.

**해결**:
- 처음부터 큰 서브넷 (`/22` = 1022 IP, `/20` = 4094 IP) 사용
- Pod 전용 보조 CIDR 추가 (`100.64.0.0/16`)
- Prefix Delegation은 IP 더 빠르게 소모하므로 주의

---

## 3. AWS LB Controller IAM 권한 누락

**증상**: Ingress 만들었는데 ADDRESS 안 채워짐, 컨트롤러 로그에 `AccessDenied`.

**진단**:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```

흔한 메시지:
```
failed to create load balancer: AccessDenied: User: ... is not authorized to perform: elasticloadbalancing:CreateLoadBalancer
```

**해결**:
- IAM Policy 가 최신 버전인지 확인 (controller가 새 API를 쓰는데 정책에 없음)
- IRSA Role의 Trust 정책에 OIDC issuer가 정확히 들어있는지

```bash
aws iam get-role --role-name <role> --query 'Role.AssumeRolePolicyDocument'
```

---

## 4. Ingress 삭제했는데 ALB 가 남음

**증상**: 학습 끝났는데 콘솔에 ALB 가 보임. 비용 계속 청구.

**원인 후보**:
- group.name 어노테이션으로 다른 Ingress가 ALB 공유 중
- TargetGroupBinding 리소스가 별도로 남아있음
- Controller가 죽어서 삭제 못 함

**해결**:
```bash
kubectl get ingress -A
kubectl get targetgroupbindings -A

# 다른 Ingress가 없는데도 남으면 ALB 직접 삭제
aws elbv2 delete-load-balancer --load-balancer-arn <arn>
```

---

## 5. ALB 의 Target 이 영영 unhealthy

**증상**: ALB 만들어졌는데 Target Group 의 Target 이 모두 `unhealthy`. 외부에서 호출하면 502/503.

**원인 후보**:
- Pod 의 readinessProbe 가 실패 (자체 health check)
- ALB health check 경로가 앱에 없음 (`/healthz` vs `/`)
- 보안 그룹: ALB → 노드 (또는 Pod) 방향이 막힘

**진단**:
```bash
aws elbv2 describe-target-health --target-group-arn <arn>
# Reasons: Target.Timeout / Target.ResponseCodeMismatch 등

kubectl get pod -l app=echoserver
kubectl exec deploy/echoserver -- wget -qO- localhost:80    # 앱 자체 응답 확인
```

**해결**:
- 어노테이션으로 health check 경로 조정:
  ```yaml
  alb.ingress.kubernetes.io/healthcheck-path: /healthz
  alb.ingress.kubernetes.io/success-codes: "200,301"
  ```
- Pod 의 readinessProbe 가 정상인지
- `target-type: ip` 면 Pod 의 SG, `instance` 면 노드 SG 가 ALB 의 SG 로부터 인바운드 허용
