# 이론 — Karpenter Advanced

> **🌱 Spot 다양화 = "한 항공편이 결항돼도 우회편으로"**
> Spot 은 *땡처리 항공권* — 갑자기 회수당할 수 있다. 한 노선 (인스턴스 타입) 만 잡아두면 그게 결항되는 순간 끝.
> c5/c6/m5/m6 + 여러 AZ 로 분산하면 *전체가 동시에 결항될 확률* 이 거의 0 — 그게 Spot 운영의 핵심 트릭.

## 1. Spot 안정성의 본질

Spot 인스턴스는 AWS 가 capacity 부족 시 회수합니다 (2분 통지). 안정성은 **다양화** 로 달성:

- **인스턴스 타입 다양화**: 같은 시점에 모든 family 가 회수될 가능성은 낮음
- **AZ 다양화**: 한 AZ 의 capacity 부족이 다른 AZ 에 영향 적음
- **세대 다양화**: c5 + c6 + c7 등 여러 세대 혼합

NodePool 의 `requirements` 가 다양할수록 Karpenter 의 **Price-Capacity-Optimized** 알고리즘이 안정적인 선택을 함.

```yaml
requirements:
  - key: karpenter.k8s.aws/instance-family
    operator: In
    values: [c5, c5a, c5d, c6a, c6i, c6id, m5, m5a, m5d, m6a, m6i, m6id]
  - key: karpenter.k8s.aws/instance-cpu
    operator: In
    values: ["2", "4", "8"]
  - key: topology.kubernetes.io/zone
    operator: In
    values: [ap-northeast-2a, ap-northeast-2b, ap-northeast-2c]
```

> **🧠 "다양화는 *원하는 옵션의 폭* 을 넓히는 일"**
> 흔한 실수: requirements 를 좁히면 "내가 원하는 정확한 타입" 만 쓰는 줄 알지만, 실제론 *Spot 풀이 좁아져 회수 빈도가 폭증* 한다.
> 워크로드가 허용하는 한 instance-family / cpu / arch 옵션을 *최대한 넓게* 두는 게 안정성 + 비용 둘 다 이득.

## 2. On-Demand Fallback 패턴

Spot 이 부족할 때 자동으로 On-Demand 로 전환하는 패턴 — 두 NodePool 사용:

```yaml
# NodePool: spot
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot]
  weight: 100      # 우선순위 높음

---
# NodePool: ondemand
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: [on-demand]
  weight: 10       # 낮음 — Spot 시도 후 안 되면 여기로
```

→ Karpenter 는 weight 높은 것 먼저, 못 만들면 다음.

> **🧠 "Fallback 은 *조용히* 일어난다 — 알람 필요"**
> Spot 부족으로 On-Demand 로 넘어가도 사용자/관리자에겐 알림이 안 간다.
> 비용 폭증을 막으려면 *On-Demand 노드 수* 를 메트릭으로 감시 + 임계 초과 시 알람 — 그래야 사일런트한 비용 누수 안 생긴다.

## 3. Disruption 의 4가지 트리거

### 3.1 Empty (또는 Underutilized)
이미 lab-03 에서 다룸. `consolidationPolicy` 로 제어.

### 3.2 Drift
EC2NodeClass 또는 NodePool 의 spec 이 변하면 기존 노드가 "drift" 상태가 됨. 새 spec 으로 노드를 만들고 기존 노드를 제거 — **무중단 spec 변경**.

```bash
kubectl get nodeclaims -L karpenter.sh/drifted
```

### 3.3 Expiration
```yaml
disruption:
  expireAfter: 168h    # 7일 후 노드 강제 회전
```

→ 보안 패치 자동 반영. AMI 업데이트 시 Drift 와 함께 작동.

### 3.4 Spot Interruption
이미 lab-01 의 SQS 큐가 받음. Karpenter 가 자동으로 cordon → drain → 다른 노드 미리 만듦.

> **🧠 "Drift 가 진짜 무중단 노드 업그레이드의 정석"**
> AMI alias 만 갱신하면 Drift 가 자동 트리거 → 모든 노드가 점진 교체.
> Managed Node Group 의 surge upgrade 와 비슷하지만 *PDB / Budget 까지 존중* 하기 때문에 더 안전한 무중단 방식.

## 4. Disruption Budget

너무 많은 노드를 한번에 회수하면 워크로드 영향. Budget 으로 제한:

```yaml
disruption:
  budgets:
    - nodes: "20%"        # 동시에 20% 까지만 disruption 허용
    - nodes: "0"          # 특정 시간대 차단
      schedule: "0 9 * * mon-fri"     # 평일 09:00 시작
      duration: 8h                     # 8시간 동안 (업무 시간)
```

→ 평일 업무 시간엔 disruption 없음, 그 외엔 20% 제한.

> **🧠 "Budget = 인프라 차원의 PDB"**
> PDB 가 *워크로드 단위* 의 disruption 한도라면, Budget 은 *노드 단위* 의 disruption 한도.
> 둘 다 걸어야 진짜 안전한 자동 회전 — Budget 만 있고 PDB 가 없으면 특정 워크로드가 한꺼번에 죽을 수 있다.

## 5. Block Device 와 인스턴스 스토어

EC2NodeClass:
```yaml
blockDeviceMappings:
  - deviceName: /dev/xvda           # 루트 볼륨
    ebs:
      volumeSize: 50Gi
      volumeType: gp3
      iops: 3000
      throughput: 125
      encrypted: true

instanceStorePolicy: RAID0           # 인스턴스 스토어를 RAID0 으로 (NVMe 다중 디스크 인스턴스 타입)
```

Spot 우대 받으면서 일시 캐시/스왑이 필요한 워크로드면 인스턴스 스토어 활용.

> **🧠 "Instance Store 는 노드와 함께 사라진다 — 영구 데이터에 쓰지 마라"**
> 빠르고 무료지만 *EC2 종료/회수* 시 데이터 0.
> 빌드 캐시, 임시 셔플, 스크래치 영역엔 최고지만 DB 데이터 / 사용자 업로드는 EBS/EFS 가 정답.

## 6. NodePool 분리 패턴 (실무)

**시나리오 1 — workload-tier 별**:
- `tier-base`: 항상 켜둘 컴포넌트 (모니터링, ingress) → On-Demand
- `tier-burst`: 가변 워크로드 → Spot

**시나리오 2 — 인스턴스 종류 별**:
- `cpu`: 컴퓨팅 집약
- `memory`: 메모리 집약 (DB, 캐시)
- `gpu`: ML 워크로드 (taint 적용)

**시나리오 3 — 환경 별**:
- `prod-spot`, `prod-ondemand`
- `staging-spot`

NodePool 의 라벨 + Pod 의 nodeSelector 로 강제.

> **🧠 "NodePool 은 *너무 잘게* 나누지 마라"**
> 처음엔 2~3개 (base / burst / 특수) 정도가 적당. 5개 넘으면 *어느 Pool 에 어떤 Pod 가 갈지* 헷갈리기 시작.
> 분리 기준은 *비용/보안/성능 차이가 명확한 축* 만 — 단순한 이름 구분용 NodePool 은 운영 부담만 늘린다.

## 7. Karpenter v1 의 변화점 (2024)

- `Provisioner` (옛 v1alpha) → `NodePool` (v1)
- `AWSNodeTemplate` → `EC2NodeClass`
- 다중 disruption 정책 + Budget 도입
- Drift 가 기본 활성

기존 자료가 옛 CRD 이름을 쓰면 주의.

> **🧠 "검색 결과의 90% 가 옛 Provisioner — 공식 문서 우선"**
> Stack Overflow, 블로그 글 다수가 v1alpha 시절 YAML 이라 그대로 쓰면 클러스터에 적용 안 된다.
> Karpenter 관련 검색 시 *2024 년 이후 글 + karpenter.sh 공식* 만 신뢰하고, 의심 시 `kubectl api-resources | grep karpenter` 로 현재 CRD 확인.

다음: [lab-01-spot-diversity.md](./lab-01-spot-diversity.md)
