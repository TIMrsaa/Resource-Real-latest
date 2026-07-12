# Lab 02 — NodePool·통합 모델과 도입 판단

> NodePool/NodeClass 선언을 설계하고, 통합(consolidation)이 비용과 churn을 어떻게 맞바꾸는지 시나리오로 분석하고, Cluster Autoscaler vs Karpenter 선택과 노드 오토스케일 전반의 판단을 정리합니다.

## 1. NodePool 설계 (선언 읽기)

실제 Karpenter라면 이런 NodePool을 정의합니다. 각 필드가 무엇을 통제하는지 읽습니다.

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: general
spec:
  template:
    spec:
      requirements:
        # 어떤 인스턴스 타입 계열을 허용할지 (넓힐수록 최적화 여지↑)
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: [c, m, r]           # compute/general/memory 계열
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot, on-demand]   # 스팟 우선(싸면), 없으면 온디맨드
        - key: kubernetes.io/arch
          operator: In
          values: [amd64, arm64]      # ARM도 허용(더 저렴할 수 있음)
      nodeClassRef:
        name: default
      expireAfter: 720h               # 노드 최대 수명(30일) → 주기적 갱신(보안)
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m              # 저활용 1분 지속 시 통합
  limits:
    cpu: "1000"                       # 이 풀 총 CPU 상한 (폭주 방지)
  weight: 10                          # 여러 NodePool 우선순위
```

**읽기 포인트:**
- `requirements`를 **넓게** 열수록 Karpenter가 최적(싼) 타입을 고를 여지가 커집니다 — 하나로 고정하면 CA와 다를 바 없습니다
- `capacity-type: [spot, on-demand]`가 스팟 활용의 핵심 (싸지만 회수 위험)
- `expireAfter`로 노드를 주기적으로 새로 → 오래된 노드의 보안·드리프트 방지(09)
- `limits`가 안전장치 — 버그로 Pod가 폭증해도 무한정 노드를 만들지 않게

## 2. 통합(consolidation) 시나리오 — 비용 vs churn

```
시나리오: 낮에 부하 높음(Pod 많음), 밤에 낮음(Pod 적음)

밤이 되어 HPA가 Pod를 줄임(08):
  → 노드들이 반쯤 빔 (저활용)
  → Karpenter 통합: 남은 Pod를 적은 노드로 합치고 빈 노드 제거
  → 비용 절감 (밤에 노드 수 ↓)

하지만 통합 = Pod 재스케줄:
  합쳐지는 과정에서 Pod가 다른 노드로 이동(drain)
  → 그 순간 Pod 재시작 (상태·연결 끊김)
  → PDB가 없으면 한꺼번에 이동 → 순간 가용성↓

트레이드오프 조절:
  consolidateAfter 짧게 → 적극 통합 → 비용↓ but churn↑
  consolidateAfter 길게 → 보수적 → 안정 but 비용↑
  → 워크로드 특성으로 결정 (배치는 적극, 상태·연결 민감은 보수)
```

**핵심** — 통합은 공짜가 아닙니다. 비용 절감의 대가는 노드 churn(Pod 이동)입니다. 43의 "자동화가 물리를 숨기지만 없애지 않음"과 같습니다 — 노드가 사라지면 그 위 Pod는 반드시 어딘가로 옮겨야 합니다.

## 3. 중단 안전 — PDB와 graceful shutdown (09)

노드가 자주 생기고 사라지는 세계에서 워크로드는 **중단 내성**을 갖춰야 합니다:

```yaml
# PodDisruptionBudget — 동시에 몇 개까지 퇴거 허용
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2            # 최소 2개는 항상 유지
  selector:
    matchLabels: { app: web }
```

```
Karpenter가 노드를 통합·만료로 제거할 때:
  1. 노드를 cordon(새 Pod 안 받음)
  2. Pod를 drain — PDB를 지키며 하나씩
     → minAvailable 위반하면 대기 (한꺼번에 안 뺌)
  3. Pod가 다른 노드로 재스케줄 (또는 Karpenter가 새 노드)
  4. 노드 제거

워크로드가 갖춰야 할 것:
  - PDB (동시 퇴거 제한)
  - graceful shutdown (SIGTERM 처리, 09의 preStop)
  - 상태 외부화 (스테이트풀은 신중 — 09)
  → 이게 없으면 노드 오토스케일이 곧 장애
```

## 4. 판단 — Karpenter vs Cluster Autoscaler vs 수동

```
Karpenter가 값어치:
  다양한 워크로드(크기·아키텍처 제각각) → 딱 맞는 노드로 낭비 제거
  가변 부하 → 빠른 확장·통합으로 비용 최적
  스팟 활용 → 다양한 타입 혼합으로 회수 위험 분산
  → 비용·효율이 중요한 중대형 클러스터

Cluster Autoscaler로 충분:
  균일한 워크로드 + 소수 노드 타입
  단순·안정 우선, 오래 검증된 것 선호
  → 복잡성을 늘릴 이유가 없을 때

수동 노드 관리:
  아주 작거나(노드 몇 개) 고정 용량이면
  오토스케일 없이 고정 노드도 선택지

전제(무엇을 쓰든):
  정확한 resource requests (08) — 없으면 다 오작동
  PDB·graceful shutdown (09) — 중단 내성
  스팟은 중단 견디는 워크로드에 (스테이트풀 신중)
```

## 5. 커리큘럼 연결 — 탄력성의 전체 그림

```
완전한 오토스케일 스택:
  요청·이벤트 → Pod 스케일: HPA(08)·KEDA(18)·Knative(43)
              ↓ (Pending 발생)
  Pod → 노드 스케일: Karpenter(44)·CA
              ↓ (노드 프로비저닝)
  실제 노드 (클라우드)

→ 위(Pod)와 아래(노드)가 협력해야 진짜 탄력성
→ 각 층의 도구를 알았으니, 이제 전체를 조합할 수 있습니다
```

## 6. 정리

- NodePool은 requirements를 **넓게** 열수록 최적화 여지↑ (고정하면 CA와 같음)
- 통합(consolidation) = 비용 절감 ↔ 노드 churn(Pod 재스케줄) 트레이드오프
- 노드가 생기고 사라지는 세계 → **PDB·graceful shutdown이 필수**(09)
- 판단: 다양·가변·비용 최적화면 Karpenter, 균일·단순이면 CA, 전제는 정확한 requests(08)
- **★ Pod 층(HPA·KEDA·Knative)과 노드 층(Karpenter)이 협력해야 완전한 탄력성**
