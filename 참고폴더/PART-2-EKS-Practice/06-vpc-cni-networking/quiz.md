# 퀴즈 — 06. VPC CNI & Networking

### Q1. AWS VPC CNI 가 다른 CNI 와 가장 다른 점은?

A. iptables 기반 라우팅
B. Pod IP 가 VPC 서브넷의 진짜 IP
C. Pod 간 암호화
D. 노드별 별도 라우팅 테이블

---

### Q2. t3.medium 노드에서 VPC CNI 기본 설정 시 최대 Pod 수는?

A. 무제한
B. 약 17 (기본) 또는 ~110 (prefix delegation)
C. 정확히 50
D. 1024

---

### Q3. Prefix Delegation 활성화의 트레이드오프 두 가지를 적으세요.

---

### Q4. AWS Load Balancer Controller 를 설치하면 type=LoadBalancer Service의 기본 LB 종류는?

---

### Q5. ALB Target Group의 `target-type: ip` 와 `instance` 의 차이는?

---

### Q6. IRSA 가 ServiceAccount 의 어노테이션 한 줄로 IAM 권한을 부여하는 메커니즘은?

A. ServiceAccount이 IAM API 를 직접 호출
B. SA 토큰을 STS AssumeRoleWithWebIdentity 로 IAM Role의 임시 자격증명과 교환
C. 어노테이션이 자동으로 IAM 정책으로 변환
D. K8s 가 IAM 위에 별도 인증 서비스 제공

---

### Q7. Ingress 리소스만 만들었는데 ADDRESS 가 영영 비어있다. 점검 1순위는?

---

### Q8. `WARM_IP_TARGET=10` 의 효과를 한 줄로?

---

### Q9. AWS LB Controller가 만든 ALB가 Ingress 삭제 후에도 남는 케이스는?

A. 어노테이션 `delete=false` 가 설정됨
B. group.name 으로 다른 Ingress 가 같은 ALB 공유 중
C. CFN 자동 삭제만 가능
D. 정상 동작이라면 무조건 같이 삭제

---

### Q10. (실습 검증) 현재 클러스터의 Pod IP 풀이 VPC 어느 서브넷에서 오는지 확인하는 명령은?

---

## 정답

<details>

**Q1**: B
**Q2**: B
**Q3**: VPC IP 더 빠르게 소모, /28 block 단위 할당으로 IP 낭비 가능성 (사용 안 하는 IP가 잠겨버림)
**Q4**: NLB (어노테이션 `service.beta.kubernetes.io/aws-load-balancer-type: external` 또는 LB Controller v2.5+ 기본)
**Q5**: IP는 ALB → Pod IP 직접 (kube-proxy 우회), Instance는 ALB → 노드 NodePort
**Q6**: B
**Q7**: AWS LB Controller Pod 상태와 로그 (IAM 권한 부족, vpcId 미스매치 등)
**Q8**: 항상 사용 가능한 IP 10개를 ENI에 미리 풀로 보유, 신규 Pod 생성 시 IP 할당 지연 회피
**Q9**: B — group.name 어노테이션으로 여러 Ingress 가 ALB 공유 시, 마지막 Ingress 가 삭제되어야 ALB도 삭제
**Q10**: `kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort -u | head; aws ec2 describe-subnets --filters Name=vpc-id,Values=$(aws eks describe-cluster --name eks-study --query 'cluster.resourcesVpcConfig.vpcId' -o text) --query 'Subnets[].CidrBlock' -o table`

</details>

다음: [pitfalls.md](./pitfalls.md)
