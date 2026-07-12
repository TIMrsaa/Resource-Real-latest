# 이론 — 스케줄링 제어의 모든 손잡이

> **🌱 17세 눈높이 비유: 수학여행 방 배정**
> - **nodeSelector/nodeAffinity** = 학생의 희망서: "1층 방으로 주세요(필수)", "창가면 좋겠어요(선호)"
> - **taint/toleration** = 방문 앞 표지판: "교사 전용"(taint). 학생은 못 들어가지만 보조교사 출입증(toleration)이 있으면 가능. **단, 출입증이 있다고 그 방에 가야 하는 건 아닙니다.**
> - **podAntiAffinity** = "쟤랑 같은 방은 절대 싫어요" / podAffinity = "단짝이랑 같은 방으로"
> - **topologySpread** = 인솔 교사의 원칙: "한 반 애들을 한 층에 몰지 말고 층마다 고르게"
> - **priority/preemption** = 응급 상황: 양호실이 꽉 차면 경증 학생을 내보내고 중증 학생을 받습니다

---

## 1. 복습: 스케줄러의 2단계

Filtering(자격 미달 탈락) → Scoring(점수 매겨 1등 선택). 이 모듈의 기능들은 전부 Filter 또는 Score에 끼어드는 손잡입니다. required류·taint는 Filter에, preferred류·spread(whenUnsatisfiable: ScheduleAnyway)는 Score에 작용합니다.

## 2. nodeSelector — 가장 단순한 지목

```yaml
spec:
  nodeSelector:
    disktype: ssd            # 이 라벨이 있는 노드만 (AND, 등호만)
```

EKS 노드에 기본으로 있는 유용한 라벨들:

```
topology.kubernetes.io/zone: ap-northeast-2a     # AZ
node.kubernetes.io/instance-type: t3.medium      # 인스턴스 타입
kubernetes.io/arch: amd64                        # 아키텍처 (Graviton이면 arm64)
karpenter.sh/capacity-type: spot                 # (Karpenter) spot/on-demand
```

## 3. nodeAffinity — 표현력 있는 지목

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:    # 필수 (Filter)
        nodeSelectorTerms:
        - matchExpressions:
          - { key: kubernetes.io/arch, operator: In, values: [amd64, arm64] }
      preferredDuringSchedulingIgnoredDuringExecution:   # 선호 (Score)
      - weight: 80
        preference:
          matchExpressions:
          - { key: karpenter.sh/capacity-type, operator: In, values: [spot] }
```

- 연산자: In/NotIn/Exists/DoesNotExist/Gt/Lt — nodeSelector보다 훨씬 풍부
- `IgnoredDuringExecution`의 의미: **스케줄링 때만 봅니다.** 이미 떠 있는 Pod는 노드 라벨이 바뀌어도 쫓겨나지 않습니다

## 4. taint / toleration — 노드의 거부권

```bash
kubectl taint nodes node1 dedicated=gpu:NoSchedule     # 부여
kubectl taint nodes node1 dedicated=gpu:NoSchedule-    # 제거 (끝의 -)
```

| effect | 의미 |
|--------|------|
| NoSchedule | 새 Pod 배치 금지 (기존은 유지) |
| PreferNoSchedule | 가급적 금지 (soft) |
| **NoExecute** | 배치 금지 + **기존 Pod도 축출** |

```yaml
tolerations:
- key: dedicated
  operator: Equal          # 또는 Exists (값 무관)
  value: gpu
  effect: NoSchedule
- key: node.kubernetes.io/not-ready    # K8s가 자동으로 붙여주는 toleration
  effect: NoExecute
  tolerationSeconds: 300   # ← 노드 장애 시 5분 후 축출의 정체 (모듈 04 복선 회수)
```

> **💡 시스템 활용 예**: 노드가 NotReady가 되면 Node 컨트롤러가 `not-ready:NoExecute` taint를 붙이고, 모든 Pod에 기본 포함된 tolerationSeconds=300이 만료되며 축출됩니다. "노드 장애 복구 5분"을 줄이려면 이 값을 줄이면 됩니다 — taint가 장애 대응 메커니즘의 부품임을 보여주는 사례.

## 5. podAffinity / podAntiAffinity — Pod 간 관계

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels: { app: web }
      topologyKey: kubernetes.io/hostname     # "이 단위로" 떨어져라 (노드 단위)
```

- topologyKey가 핵심: hostname이면 "같은 노드 금지", zone이면 "같은 AZ 금지"
- 용도: 복제본 분산(anti), 캐시와 앱을 같은 노드에(affinity — 지연 감소)
- 비용: pod affinity류는 스케줄러가 **전 노드의 Pod 라벨을 검사**해야 해서 대규모 클러스터에서 비쌉니다. 단순 분산은 topologySpread가 더 효율적

## 6. topologySpreadConstraints — 균등 분산의 표준

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1                                   # 최다-최소 차이 허용치
    topologyKey: topology.kubernetes.io/zone     # AZ 단위로
    whenUnsatisfiable: DoNotSchedule             # 못 지키면 Pending (ScheduleAnyway = soft)
    labelSelector:
      matchLabels: { app: web }
```

"web Pod들을 AZ끼리 최대 1개 차이로 유지" — replicas 6, AZ 3개면 2/2/2. anti-affinity(전부 다른 곳, 0 또는 1)보다 유연하고 쌉니다.

> 기본값으로도 약한 spread가 적용되지만(클러스터 기본 제약), **고가용성이 필요한 서비스는 명시**가 정석.

## 7. PriorityClass와 선점

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: critical }
value: 1000000            # 높을수록 우선
preemptionPolicy: PreemptLowerPriority   # (기본) 자리 없으면 낮은 우선순위를 축출
---
# Pod에서: spec.priorityClassName: critical
```

- 자리가 없을 때: 스케줄러가 **낮은 priority Pod를 축출(preempt)** 해서라도 높은 Pod를 배치
- 내장: `system-cluster-critical`/`system-node-critical` (CNI, kube-proxy 등이 사용 — 시스템이 일반 앱에 밀려나지 않는 이유)
- 운영 패턴: critical(결제) > normal(기본) > batch(밤샘 작업, `preemptionPolicy: Never`로 양보만)

## 8. 소스코드에서 확인하기

- Filter/Score 플러그인들: `pkg/scheduler/framework/plugins/` — nodeaffinity, tainttoleration, podtopologyspread 디렉터리가 위 기능 그대로 1:1 대응 (고급 모듈 25에서 프레임워크 전체 해부)

## 요약 카드

| 질문 | 답 |
|------|----|
| taint의 주체? | **노드** (Pod를 밀어냄). toleration은 입장권일 뿐 지정석 아님 |
| GPU 노드 전용 배치 공식? | taint+toleration(남들 차단) **+ nodeAffinity**(거기로 보냄) |
| 노드 장애 5분 축출의 정체? | not-ready NoExecute taint + tolerationSeconds 300 |
| AZ 균등 분산? | topologySpreadConstraints (maxSkew=1, zone) |
| required의 위험? | 못 맞추면 Pending — soft(preferred/ScheduleAnyway) 우선 검토 |
