# 이론 — Karpenter

> **🌱 Karpenter = "Uber 식 즉시 차량 호출"**
> Cluster Autoscaler 는 *정해진 차종의 셔틀버스 (ASG)* 를 시간표대로 늘리는 방식.
> Karpenter 는 "지금 손님 (Pending Pod) 이 4명 + 짐 많음 → 미니밴 1대" 같이 *그때그때 맞춤 차량* 을 부르는 방식이라 빠르고 알뜰하다.

## 1. 노드 자동 스케일러의 진화

### 1.1 Cluster Autoscaler (CA) — 옛날 방식

```
[Pending Pod 발생]
    ↓
[CA] Auto Scaling Group의 desired_capacity 를 늘려달라고 요청
    ↓
[ASG] 새 EC2 띄움 (몇 분 걸림)
    ↓
[새 노드가 클러스터 join]
    ↓
[Pending Pod 가 그 노드에 스케줄]
```

**한계**:
- ASG 의 인스턴스 타입이 고정 (또는 Mixed Instances Policy로 제한적 다양화)
- "Pending Pod 의 요구사항" 과 "노드 사양" 이 안 맞아도 ASG 단위로 늘림 → 비효율
- ASG 1개당 1 AZ 권장 → 다중 AZ 면 ASG 여러 개 → 관리 복잡

### 1.2 Karpenter — 새로운 접근

```
[Pending Pod 발생]
    ↓
[Karpenter] Pod 의 requests/affinity 분석
    ↓
[Karpenter] EC2 API 직접 호출 → 정확히 맞는 인스턴스 타입 선택 + Spot 우선
    ↓
[새 노드가 join] (보통 30~60초)
    ↓
[Pod 즉시 스케줄]
```

**장점**:
- ASG 없음 — Karpenter 가 EC2 직접 관리
- 인스턴스 타입을 Pod 요구사항에 맞춰 동적 선택 (예: Pod 가 4Gi 메모리 → m5.large 자동 선택)
- 다중 인스턴스 타입 동시 고려 (Spot 가격 / 가용성)
- **Consolidation** — 사용 적은 노드를 자동 통합/제거
- 다중 AZ 자동 분산

> **🧠 "Karpenter 의 핵심 차별점은 *EC2 직접 호출*"**
> ASG 를 거치지 않으니 인스턴스 타입 / Spot 가격 / AZ 를 *Pod 단위로* 최적화한다.
> CA 가 "ASG 의 desired_capacity 를 늘려달라" 라면, Karpenter 는 "이 Pod 에 정확히 맞는 EC2 한 대 띄워라" — 의사결정 단위가 다르다.

## 2. Karpenter 핵심 CRD

### 2.1 NodePool — "어떤 Pod 들을 받을 노드 그룹인가"

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        workload-type: general
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: [amd64]
        - key: kubernetes.io/os
          operator: In
          values: [linux]
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot]            # Spot 우선
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: [c, m, r]
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values: ["2", "4", "8"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: "100"          # 이 NodePool 이 만들 수 있는 최대 합산 CPU
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
```

### 2.2 EC2NodeClass — "어떤 EC2 를 만들 것인가"

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2023            # Amazon Linux 2023 (또는 Bottlerocket, AL2)
  amiSelectorTerms:
    - alias: al2023@latest
  role: KarpenterNodeRole-eks-study
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: eks-study
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: eks-study
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 30Gi
        volumeType: gp3
        encrypted: true
  tags:
    Project: eks-study
    Provisioner: karpenter
```

### 2.3 NodeClaim — Karpenter 내부

NodePool 이 새 노드를 만들기 위해 자동 생성하는 중간 객체. 사용자가 직접 만들 일은 없음. 디버깅 시 `kubectl get nodeclaims` 로 노드 생성 진행 상황 확인.

> **🧠 "NodePool = WHO, EC2NodeClass = WHAT"**
> NodePool 은 *어떤 Pod 를 받을지 / 어떤 인스턴스 카테고리를 쓸지* 정책, EC2NodeClass 는 *실제 EC2 launch template 수준 설정* (AMI, IAM Role, EBS).
> 둘을 분리하기 때문에 한 EC2NodeClass 를 여러 NodePool 이 공유할 수 있다 — 운영 환경/팀 구분에 유용.

## 3. Pod 가 어느 NodePool 로 가는가

스케줄러는 다음 순서로 결정:
1. Pod 의 `nodeSelector`, `affinity`, `tolerations` 와 **호환되는 NodePool** 선택
2. 여러 NodePool 호환이면 `weight` 가 높은 것 우선 (NodePool 의 `spec.weight`)
3. 호환 노드 中 Spot 가격이 낮은 인스턴스 타입 우선

→ 일반 NodePool + GPU 전용 NodePool 같은 분리 시 라벨/taint 로 강제.

> **🧠 "기본 NodePool 만 두면 모든 Pod 가 거기로 몰린다"**
> Pod 가 *어느 NodePool 로 갈지* 명시 안 하면 호환되는 첫 NodePool 로 — 비싼 GPU 노드에 일반 Pod 가 가는 사고 발생 가능.
> 전용 NodePool 은 *taint* 로 막고, 그 워크로드만 *toleration* 으로 통과하게 설계해야 안전.

## 4. Disruption (회수) 정책

### 4.1 Consolidation — 효율 개선

- `WhenEmpty`: 노드가 비면(모든 Pod 빠짐) 회수
- `WhenEmptyOrUnderutilized`: 비거나 사용률이 낮으면 회수 (다른 노드로 이전 가능 시)
- `consolidateAfter`: 회수 결정 전 대기 시간

### 4.2 Drift — 설정 변경 감지

EC2NodeClass 또는 AMI 변경 시 기존 노드들이 "drift" 상태가 되어 자동 교체. 무중단 배포처럼 동작.

### 4.3 Expiration — 강제 만료

```yaml
disruption:
  expireAfter: 720h     # 30일 후 노드 강제 교체
```

→ 보안 패치 자동 반영. 학습용은 길게 또는 비활성.

### 4.4 Spot Interruption Handling

Spot 노드가 회수 통지를 받으면(2분 전), Karpenter 가 자동으로:
1. 노드를 cordon (새 Pod 배치 차단)
2. drain (기존 Pod 우아하게 이전)
3. 다른 노드 미리 만들기

EKS 의 SQS 큐로 EC2 Spot Interruption / Health Event 받음 → IRSA로 큐 읽기 권한 필요.

> **🧠 "Consolidation 이 Spot 비용 절감의 진짜 무기"**
> Spot 가격 자체보다 *놀고 있는 노드를 빠르게 회수* 하는 게 청구서 절감 효과가 더 크다.
> `WhenEmptyOrUnderutilized` + 짧은 `consolidateAfter` 조합이 운영의 기본값 — 단, 너무 짧으면 노드가 너무 자주 회전해서 비용 vs 안정성 균형 필요.

## 5. Cluster Autoscaler 와 비교 표

| | Cluster Autoscaler | Karpenter |
|---|---|---|
| 대상 | ASG/MIG 단위 | EC2 직접 |
| 인스턴스 타입 선택 | ASG 의 fleet 정의 | Pending Pod 요구에 맞춤 동적 |
| Spot 다양성 | Mixed Instance Policy | 자유롭게 다중 |
| Consolidation | ❌ (별도 도구 필요) | ✅ 내장 |
| Multi-AZ | ASG/AZ 별 | 자동 |
| 출시 | 2016 (mature) | 2021 (성숙 빠르게) |
| 운영 부담 | 중 | 낮 |

→ **EKS 신규 클러스터는 Karpenter 권장**.

> **🧠 "기존 ASG/CA 가 있어도 Karpenter 와 공존 가능"**
> Karpenter 의 NodePool 과 CA 의 ASG 는 서로 모른 척 동작 — 점진 마이그레이션 가능.
> 단, *같은 Pod 가 양쪽에서 동시에 노드 요청* 하지 않게 라벨/taint 로 영역을 명확히 나눠야 한다.

## 6. 설치 흐름 (다음 lab)

1. IAM Role 생성 (Karpenter Controller 가 EC2 / IAM / SQS 호출 권한)
2. IAM Role for Karpenter Nodes (노드가 ECR pull / SSM 등)
3. SQS 큐 생성 (Spot Interruption 받기)
4. EventBridge Rule (EC2 이벤트 → SQS)
5. 클러스터 서브넷 / SG 에 `karpenter.sh/discovery=eks-study` 태그
6. Helm install Karpenter

복잡해 보이지만 `karpenter.sh` 공식 가이드의 CFN 템플릿이 5번까지 한 번에.

> **🧠 "Karpenter 설치 실패의 90% = 태그 / IRSA"**
> 노드가 안 뜨면 subnet/SG 의 `karpenter.sh/discovery` 태그 + Controller SA 의 IAM 권한 두 가지부터 확인.
> 로그가 "no instances" 라면 NodePool requirements 가 너무 엄격해서 매칭되는 인스턴스 타입이 없을 가능성도.

다음: [lab-01-install.md](./lab-01-install.md)
