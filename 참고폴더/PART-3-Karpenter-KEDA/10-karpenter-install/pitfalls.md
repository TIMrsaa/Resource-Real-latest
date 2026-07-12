# 흔한 함정 5선 — 10. Karpenter Install

## 1. EC2NodeClass 가 영영 NotReady

**증상**: `kubectl get ec2nodeclass` 의 READY 가 `False`.

**원인 후보**:
- 서브넷에 `karpenter.sh/discovery=<cluster>` 태그 누락
- 보안그룹에 같은 태그 누락
- IAM Role (KarpenterNodeRole) 이름 오타

**진단**:
```bash
kubectl describe ec2nodeclass default
# status.conditions 의 message 확인
```

**해결**:
```bash
# 서브넷 태그 다시 추가
SUBNETS=$(aws eks describe-cluster --name eks-study --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
aws ec2 create-tags --resources $SUBNETS --tags Key=karpenter.sh/discovery,Value=eks-study
```

---

## 2. NodeClaim 이 만들어졌는데 노드가 안 join 함

**증상**: NodeClaim Ready=False, EC2 인스턴스는 떠 있지만 `kubectl get nodes` 에 안 보임.

**원인**:
- KarpenterNodeRole 이 클러스터의 RBAC (aws-auth 또는 Access Entries) 에 등록 안 됨
- 노드의 보안그룹이 클러스터 API 접근 차단

**진단**:
```bash
INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=default" Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[0].InstanceId' --output text)
aws ec2 get-console-output --instance-id $INSTANCE --output text | tail -50
# kubelet 의 인증/인가 에러 메시지 확인
```

**해결**: lab-01 의 Access Entries 또는 aws-auth 단계 재실행.

---

## 3. Karpenter 가 잘못된 인스턴스 타입을 만듦 (너무 큰)

**증상**: Pod 1개를 위해 m5.4xlarge 같은 큰 노드 만듦.

**원인**: NodePool 의 `requirements` 에 `instance-cpu`, `instance-memory`, `instance-category` 제약 부족.

**해결**: NodePool 수정:
```yaml
requirements:
  - key: karpenter.k8s.aws/instance-cpu
    operator: In
    values: ["2", "4"]    # 큰 인스턴스 배제
  - key: karpenter.k8s.aws/instance-category
    operator: In
    values: [c, m, t]    # GPU/메모리 최적화 등 배제
```

---

## 4. Spot 노드가 너무 자주 회수되어 워크로드 불안정

**증상**: 클러스터에 `Node Not Ready` 이벤트 다수, Pod 들이 자주 옮겨다님.

**원인**:
- 단일 인스턴스 타입 만 선택 — 그 타입의 Spot 회수율이 높을 때 영향 큼
- 단일 AZ 만 사용

**해결**: Karpenter 의 다양화 설정:
```yaml
requirements:
  - key: karpenter.k8s.aws/instance-family
    operator: In
    values: [c5, c5a, c6a, c6i, m5, m5a, m6a, m6i]    # 여러 family
  - key: topology.kubernetes.io/zone
    operator: In
    values: [ap-northeast-2a, ap-northeast-2b, ap-northeast-2c]
```

또한 PDB 적용으로 동시 회수 영향 제한.

---

## 5. Karpenter Controller 가 OOMKilled

**증상**: Karpenter Pod 의 RESTARTS 가 자주 증가. 로그에 `signal: killed`.

**원인**: 노드/Pod 수가 많은 클러스터에서 Karpenter 의 메모리 사용이 기본 limits (256Mi 등) 초과.

**해결**:
```bash
helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter \
  --reuse-values \
  -n karpenter \
  --set controller.resources.requests.memory=512Mi \
  --set controller.resources.limits.memory=1Gi
```

또는 컨트롤러 replicas 늘리기 (HA 외에는 메모리 한계 그대로).
