# 흔한 함정 5선 — 05. EKS 클러스터

## 1. CFN Stack 삭제 실패

**증상**: `eksctl delete cluster` 가 멈추거나 timeout.

**원인 후보**:
- LoadBalancer Service가 만든 NLB/ALB 가 남아있어 VPC 삭제 차단
- ENI (Elastic Network Interface) 가 정리 안 됨
- IAM Role을 다른 자원이 참조 중

**해결**:
```bash
# 1. 클러스터의 모든 Service of type LoadBalancer 삭제 (선행)
kubectl get svc -A | grep LoadBalancer
kubectl delete svc <name> -n <ns>

# 2. eksctl delete 재시도
eksctl delete cluster --name eks-study --region ap-northeast-2 --wait

# 3. 그래도 stuck 이면 CFN 콘솔에서 stack 삭제 (Retain Resources 옵션 사용)
```

NLB/ALB 가 외부에 남으면 VPC 삭제가 안 됩니다 — 이게 가장 흔한 원인.

---

## 2. NAT Gateway 비용 폭탄

**증상**: AWS 비용 1주일 동안 $50 청구. 분석해보면 NAT Gateway 데이터 전송이 대부분.

**원인**: 
- ECR pull 트래픽이 NAT Gateway를 통해 나감 (퍼블릭 인터넷)
- 각 Pod 시작마다 ECR에서 이미지 pull → 누적

**해결**:
- VPC Endpoint (ECR API + ECR DKR + S3) 추가 → ECR pull 이 VPC 내부로
- imagePullPolicy: IfNotPresent (이미지 캐싱 활용)
- 노드 디스크 큰 사이즈 → 노드 라이프사이클 동안 캐시 유지

```yaml
# ClusterConfig 에 추가 가능
vpc:
  serviceEndpoints:
    - ecr.api
    - ecr.dkr
    - s3
```

---

## 3. Spot 인스턴스 종료로 워크로드 출렁

**증상**: 갑자기 Pod 다수가 Pending 또는 NotReady.

**원인**: Spot 인스턴스가 회수됨 (capacity 부족).

**완화**:
- 다중 인스턴스 타입 (`instanceTypes: [t3.medium, t3a.medium]` 같은 동일 vCPU/메모리 스펙으로 묶기)
  - ⚠️ Managed Node Group + Spot은 같은 vCPU/RAM 비율의 인스턴스끼리 섞어야 함 — `t3.medium`(2vCPU/4Gi)과 `t3.large`(2vCPU/8Gi)는 메모리 차이로 섞으면 ASG가 거부함
  - 더 다양화하려면 `c` 패밀리처럼 동일 스펙 클래스 안에서 세대/벤더만 다른 조합: `[c7i.large, c7a.large, c6i.large, c6a.large]`
- 다중 AZ (기본)
- PodDisruptionBudget 으로 동시 회수 영향 제한
- AWS Node Termination Handler (DaemonSet) 설치 → Spot 종료 통지를 받아 Pod 우아한 종료
- 중요 워크로드는 On-Demand 노드 그룹에 배치

---

## 4. addon 버전 mismatch

**증상**: 클러스터 1.35 로 업그레이드했는데 vpc-cni 가 이전 K8s 마이너 버전용으로 그대로.

**원인**: addon은 클러스터 업그레이드와 별도로 업그레이드 필요.

**해결**:
```bash
eksctl utils describe-addon-versions --kubernetes-version 1.35 --name vpc-cni \
  --query 'Addons[].AddonVersions[].AddonVersion' --output text | head -1
# 첫 결과가 권장 버전

eksctl update addon --name vpc-cni --version <버전> --cluster eks-study --force
```

업그레이드 순서: **클러스터 → addon → 노드 그룹** 권장.

---

## 5. kubectl context 헷갈림

**증상**: 명령이 엉뚱한 클러스터에 들어감.

**원인**: 여러 EKS 클러스터를 다루며 `kubectl config use-context` 누락.

**해결**:
```bash
kubectl config current-context        # 항상 확인하는 습관
kubectl config get-contexts
kubectl config use-context <name>

# kubectx 도구 사용
brew install kubectx
kubectx                              # 컨텍스트 목록 + 전환
```

쉘 프롬프트에 컨텍스트 표시 권장:
```bash
# zsh
PROMPT='%n %1~ $(kubectl config current-context 2>/dev/null) > '
```
