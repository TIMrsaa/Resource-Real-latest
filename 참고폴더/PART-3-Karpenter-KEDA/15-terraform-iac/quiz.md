# 퀴즈 — 15. Terraform IaC

### Q1. Terraform 의 state 가 의미하는 것은?

---

### Q2. `terraform-aws-modules/eks/aws` 모듈이 한 번에 만들어주는 것 4가지?

---

### Q3. `helm_release` Terraform 리소스의 장점은?

---

### Q4. Karpenter 의 NodePool/EC2NodeClass 를 Terraform 으로 관리하는 방법은?

A. `kubernetes_manifest` 리소스 사용
B. `helm_release` 의 values 에 inline
C. K8s YAML 을 별도 적용 (Terraform 외부)
D. 모두 가능

---

### Q5. `single_nat_gateway: true` 의 트레이드오프는?

---

### Q6. `terraform plan -out tf.plan` 후 `terraform apply tf.plan` 의 의미는?

---

### Q7. workspace 와 디렉토리 분리 중 운영 권장은? 이유는?

---

### Q8. tfstate 가 손상되면 (예: 실수로 삭제) 어떻게 복구?

---

### Q9. `terraform destroy` 가 멈추는 흔한 원인은?

A. AWS API rate limit
B. K8s LoadBalancer 가 만든 ALB 가 VPC 삭제 차단
C. tfstate 손상
D. (A)와 (B)

---

### Q10. (실습 검증) Terraform 으로 만든 클러스터의 주요 IAM Role 들을 한 번에 보는 명령은?

---

## 정답

<details>

**Q1**: 마지막 apply 시점의 모든 리소스의 ID + 속성. Terraform 은 이걸 기반으로 다음 변경 분석
**Q2**: VPC 연결, Cluster IAM Role, Cluster 자체, addon 설치, Managed Node Group, OIDC provider 등
**Q3**: Helm 차트 + values 가 Terraform state 로 관리되어 다른 리소스와 의존성 / 변경 추적 통합
**Q4**: D (학습 외에는 A 권장)
**Q5**: 비용 절감 (NAT GW 1개 = $0.045/h vs 3개) ↔ AZ 장애 시 다른 AZ Pod 의 인터넷 접속 단절
**Q6**: plan 결과를 파일로 저장한 뒤 apply 가 정확히 그 plan 만 실행 (CI/CD 에서 review-apply 분리 패턴)
**Q7**: 디렉토리 분리. tfstate 분리 / IAM 분리 / 코드 의도 명확. workspace 는 단일 코드의 환경 변동만 다룰 때.
**Q8**: 마지막 백업 복원, 또는 `terraform import` 로 기존 자원 다시 매핑
**Q9**: D
**Q10**: `terraform output | grep iam_role`

</details>

다음: [pitfalls.md](./pitfalls.md)
