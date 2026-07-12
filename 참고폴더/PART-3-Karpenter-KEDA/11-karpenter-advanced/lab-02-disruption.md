# Lab 02 — Drift, Expiration, Disruption Budget

## 학습 확인 포인트

- [ ] EC2NodeClass 변경 시 Drift 가 발생함
- [ ] Karpenter 가 Drift 노드를 무중단 교체
- [ ] Disruption Budget 으로 동시 회수 제한 확인

> **🌱 핵심 개념 미리보기**
> - **Drift**: 노드의 실제 spec 이 NodePool/EC2NodeClass 의 현재 spec 과 차이날 때 → Karpenter 가 자동 교체.
> - **Expiration**: `expireAfter` 시간이 지난 노드 자동 회전. AMI 패치/보안 업데이트에 유용.
> - **Disruption Budget**: 동시에 몇 % 노드를 회수할지 제한. 서비스 영향 최소화.
> - **PDB (PodDisruptionBudget)**: K8s 표준. Pod 수준에서 최소 가용 보장. Karpenter 가 evict 시 존중.
> - **Consolidation**: 비효율 노드(under-utilized) 자동 회수. drift 와 별개의 disruption 종류.

## 1. Drift 시연 — EC2NodeClass 변경

먼저 노드 몇 대 띄우기:
```bash
kubectl scale deploy inflate --replicas=3
sleep 60
kubectl get nodes -L nodepool | grep karpenter
```

EC2NodeClass 의 volumeSize 변경 (drift 트리거):
```bash
kubectl patch ec2nodeclass default --type=merge \
  -p '{"spec":{"blockDeviceMappings":[{"deviceName":"/dev/xvda","ebs":{"volumeSize":"40Gi","volumeType":"gp3","encrypted":true}}]}}'
```

watch 노드 변화:
```bash
watch -n2 kubectl get nodeclaims -L karpenter.sh/drifted
```

기대 (1~2분 후):
```
NAME             TYPE         CAPACITY  ZONE              READY   AGE   DRIFTED
default-aaaaa    c5a.large    spot      ap-northeast-2a   True    5m    Drifted   ← 옛 spec
default-bbbbb    c5a.large    spot      ap-northeast-2a   True    1m              ← 새 spec
default-ccccc    m6a.large    spot      ap-northeast-2b   True    30s             ← 새 spec
```

오래된 노드가 Drift 마크 → Karpenter 가 점진적 교체 (Disruption Budget 따라).

> **🧠 Drift 가 점진적인 이유**
> Karpenter 는 주기적(15초)으로 NodeClaim 의 실제 launchTemplate hash 와 현재 EC2NodeClass hash 를 비교 → 다르면 `Drifted` 컨디션.
> Drifted 노드를 한꺼번에 모두 회수하면 서비스 영향 큼 → Disruption Budget(예: 20%) 으로 제한.
> 신규 노드 띄우고 → drain → 종료 순서. 항상 capacity 먼저 확보 후 옛 노드 정리.

```bash
sleep 180
kubectl get nodes -L nodepool       # 모든 노드가 새 spec 으로 교체됨
```

## 2. AMI Drift 시연

EC2NodeClass 의 amiSelectorTerms 가 `alias: al2023@latest` 면 새 AMI 출시 시 자동 drift.

```bash
# 현재 AMI ID
kubectl get nodeclaims -o custom-columns=NAME:.metadata.name,AMI:.status.imageID
```

새 AMI 가 안 나왔으면 변화 없음. 강제 시뮬레이션은 amiSelectorTerms 를 특정 ID 로 고정 후 다른 ID 로 변경.

> **🧠 `alias: al2023@latest` 의 함정**
> 편하지만 위험. AWS 가 새 AMI 출시하는 순간 모든 노드가 동시 drift → 하룻밤 사이 클러스터 전체 회전 가능.
> 운영에서는 `al2023@v20240101` 처럼 버전 핀하고, 정기 점검에서 수동 업데이트.
> 또는 budget 으로 동시 교체율 제한 + PDB 로 critical 워크로드 보호.

## 3. Expiration 시연

NodePool 의 `expireAfter` 가 만료되면 자동 회전:

```bash
kubectl patch nodepool spot --type=merge -p '{"spec":{"template":{"spec":{"expireAfter":"5m"}}}}'

# 새 노드의 age 가 5분 넘으면 자동 교체
sleep 360
kubectl get nodes -L nodepool        # 회전 결과
```

원복:
```bash
kubectl patch nodepool spot --type=merge -p '{"spec":{"template":{"spec":{"expireAfter":"168h"}}}}'
```

## 4. Disruption Budget 시연

NodePool 에 `budgets: [- nodes: "20%"]` 적용 (이미 manifest 에 있음).

여러 노드 띄우고 동시 disruption 유발:
```bash
kubectl scale deploy inflate --replicas=10
sleep 90
kubectl get nodes -L nodepool | grep karpenter | wc -l    # 노드 수 N

# 한꺼번에 사용량 줄이기 (Pod 모두 삭제 → 빈 노드 다수)
kubectl scale deploy inflate --replicas=0
```

watch:
```bash
watch -n2 kubectl get nodes -L nodepool
```

기대: N개의 빈 노드가 한 번에 사라지지 않고 20% 씩 단계적 회수. (예: 5개 노드면 한 번에 1개씩)

> **🧠 budget 의 정확한 의미**
> `nodes: "20%"` = 동시에 disruption 가능한 노드 수가 전체의 20% 까지. 5개면 1개, 100개면 20개.
> 이 값이 `0` 이면 disruption 완전 차단 (Drift/Expiration/Consolidation 모두 멈춤).
> 단, AWS Spot 회수 같은 외부 강제 종료는 budget 무시 (Karpenter 가 막을 수 없음).

## 5. Schedule 기반 Budget — 평일 업무 시간 보호

```bash
kubectl patch nodepool spot --type=merge -p '{
  "spec":{
    "disruption":{
      "budgets":[
        {"nodes":"20%"},
        {"nodes":"0", "schedule":"0 9 * * mon-fri", "duration":"8h"}
      ]
    }
  }
}'
```

평일 09:00 ~ 17:00 동안 disruption 차단. 중요 시간대 보호.

## 6. PDB 와 결합

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: critical
spec:
  minAvailable: 80%
  selector: {matchLabels: {tier: critical}}
```

→ Karpenter 가 회수 결정해도 PDB 가 막으면 못 함. 두 안전장치 결합.

> **🧠 PDB vs Disruption Budget 의 책임 분리**
> | 레벨 | 보호 대상 | 누가 검사 |
> |------|----------|----------|
> | NodePool budget | 노드 회수율 | Karpenter |
> | PDB | Pod evict 안전성 | K8s API server |
>
> PDB 가 너무 빡빡(`minAvailable: 100%`)하면 evict 못 해서 노드 stuck → `kubectl get events` 에 `Cannot evict pod` 로그.

## 7. 정리

```bash
kubectl scale deploy inflate --replicas=0
```

## 학습 확인 질문

1. Drift 가 트리거되는 spec 변경 종류는?
2. Disruption Budget 의 `nodes: "20%"` 가 정확히 의미하는 것은?
3. PDB 가 너무 빡빡하면 Karpenter 회수가 못 일어나는데, 어떻게 진단?

다음: [lab-03-cost-explorer.md](./lab-03-cost-explorer.md)
