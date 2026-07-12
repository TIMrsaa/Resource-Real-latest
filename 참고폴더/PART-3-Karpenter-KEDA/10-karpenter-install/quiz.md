# 퀴즈 — 10. Karpenter Install

### Q1. Karpenter 가 Cluster Autoscaler 와 다른 핵심 차이는?

A. ASG 단위 vs EC2 직접
B. K8s 버전 호환성
C. 다중 클러스터 지원
D. Helm 으로 설치

---

### Q2. Karpenter 의 두 핵심 CRD 이름은?

---

### Q3. Pod 의 nodeSelector / requirements 와 호환되는 NodePool 이 여러 개일 때 우선순위 결정 기준은?

---

### Q4. Karpenter 가 Spot Interruption 통지를 받는 경로는?

A. EC2 메타데이터 직접 폴링
B. EventBridge → SQS → Karpenter Controller
C. CloudWatch Logs
D. Kubernetes events

---

### Q5. EC2NodeClass 의 `subnetSelectorTerms` 가 매칭하는 조건은?

---

### Q6. Consolidation 의 `WhenEmpty` 와 `WhenEmptyOrUnderutilized` 의 차이는?

---

### Q7. NodePool 의 `limits.cpu: 100` 의 의미는?

A. 클러스터 전체 CPU 100 core
B. 이 NodePool 이 만들 수 있는 노드들의 합산 CPU 100 core
C. 노드 1대의 최대 CPU
D. 워크로드 1개의 최대 CPU

---

### Q8. NodeClaim 객체의 역할은?

---

### Q9. Karpenter Controller 가 동작하기 위한 IAM 권한 카테고리 3가지를 적으세요.

---

### Q10. (실습 검증) Karpenter 가 만든 모든 EC2 인스턴스를 한 줄로 보는 명령은?

---

## 정답

<details>

**Q1**: A
**Q2**: NodePool, EC2NodeClass (그리고 NodeClaim 은 내부 자동 생성)
**Q3**: NodePool 의 `spec.weight` (높을수록 우선). 그 후 Spot 가격/가용성.
**Q4**: B
**Q5**: 해당 태그를 가진 서브넷 모두 — 본 lab 에서는 `karpenter.sh/discovery=eks-study`
**Q6**: WhenEmpty 는 노드가 완전히 빈 경우만 회수. WhenEmptyOrUnderutilized 는 사용률 낮고 Pod 이전 가능 시도 회수 (더 적극적)
**Q7**: B
**Q8**: NodePool 이 새 노드를 만들기 위해 자동 생성하는 중간 객체. 노드 생성 진행 상황 추적용. 사용자 직접 조작 X.
**Q9**: EC2 (인스턴스 생성/종료/태깅), IAM (PassRole — 노드 IAM Role 부여), SQS (Spot Interruption 큐 읽기). 추가로 EKS, Pricing 등.
**Q10**: `aws ec2 describe-instances --filters Name=tag:karpenter.sh/nodepool,Values=default Name=instance-state-name,Values=running --query 'Reservations[].Instances[].[InstanceId,InstanceType,InstanceLifecycle]' --output table`

</details>

다음: [pitfalls.md](./pitfalls.md)
