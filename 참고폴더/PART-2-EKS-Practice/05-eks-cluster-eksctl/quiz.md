# 퀴즈 — 05. EKS 클러스터 (eksctl)

### Q1. EKS Control Plane 의 책임은? (사용자 책임이 아닌 것 모두)

A. etcd 백업
B. kube-apiserver 패치
C. 워커 노드 OS 업데이트
D. CNI 플러그인 동작

---

### Q2. eksctl이 클러스터 생성 시 만드는 CFN Stack 의 종류 두 가지는?

---

### Q3. `iam.withOIDC: true` 가 가능하게 하는 핵심 기능은?

---

### Q4. NAT Gateway 를 `Single` 로 설정한 단점은?

A. NAT Gateway 비용이 더 비쌈
B. AZ 장애 시 다른 AZ의 Pod도 인터넷 접속 불가
C. 보안 그룹 자동 설정 불가
D. EKS 호환성 문제

---

### Q5. Spot 인스턴스 노드의 Pod이 갑작스레 종료될 때 K8s가 받는 신호는?

A. 노드가 갑자기 사라짐
B. 약 2분의 종료 알림 (interruption notice) 후 graceful shutdown 시도
C. AWS Console에서만 알 수 있음
D. 영향 없음

---

### Q6. EKS Access Entries 가 aws-auth ConfigMap을 대체하는 이유는?

---

### Q7. Managed Node Group 과 Self-managed 의 차이를 한 줄로?

---

### Q8. addon 버전 업그레이드 시 conflictResolution 옵션의 의미는?

---

### Q9. `eksctl scale nodegroup --nodes 5` 명령의 한계는?

A. 클라우드 비용이 자동 증가하지 않음
B. ASG 의 max 보다 큰 값을 지정할 수 없음
C. minSize 보다 작아질 수 없음
D. (B)와 (C) 모두

---

### Q10. (실습 검증) 현재 클러스터의 노드 그룹 이름과 인스턴스 타입을 한 줄로 보는 명령은?

---

## 정답

<details>

**Q1**: A, B (Control Plane 책임). C, D는 사용자 책임 (Managed NG에서도 OS는 자동 업데이트되지만 트리거는 사용자가)
**Q2**: `eksctl-<cluster>-cluster` (VPC + Cluster), `eksctl-<cluster>-nodegroup-<name>` (각 노드 그룹), 그 외 addon별 stack
**Q3**: IRSA (IAM Roles for Service Accounts). OIDC provider가 있어야 K8s SA의 토큰을 IAM이 인증 가능
**Q4**: B
**Q5**: B
**Q6**: ConfigMap 편집은 race condition / 실수 위험 / RBAC 분리 어려움. Access Entries는 IAM 정책처럼 API로 관리
**Q7**: Managed는 AWS가 ASG 자동 관리, Self-managed는 사용자가 ASG/AMI 직접 관리 (자유도 vs 운영 부담)
**Q8**: PRESERVE (기존 K8s 설정 유지) / OVERWRITE (addon 기본값으로 덮어쓰기)
**Q9**: D
**Q10**: `eksctl get nodegroup --cluster eks-study -o json | jq -r '.[]|"\(.Name)\t\(.InstanceType)"'`

</details>

다음: [pitfalls.md](./pitfalls.md)
