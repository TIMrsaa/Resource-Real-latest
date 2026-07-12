# Lab 03 — Consolidation (노드 자동 회수)

## 학습 확인 포인트

- [ ] Pod 줄이면 노드가 자동으로 회수됨을 확인
- [ ] `consolidationPolicy` 의 두 모드 차이 체험
- [ ] 노드 회수 시 Pod 가 다른 노드로 우아하게 이동하는 것을 봄

> **🌱 Consolidation (통합) 이란?**
> "쓰지 않는 노드를 자동으로 회수해서 비용 절감" 하는 Karpenter 핵심 기능.
> 단순히 빈 노드 회수 뿐 아니라 **저활용 노드의 Pod을 다른 노드로 옮기고 노드 종료** 도 포함.
>
> 예:
> ```
>   노드 A (c5.large): Pod x 1개 (10% 사용)
>   노드 B (c5.large): Pod x 2개 (30% 사용)
>     ↓ Karpenter 판단: 둘을 하나로 합칠 수 있겠는데?
>   노드 C (c5.large) 새로 띄움 → A,B Pod 모두 이전 → A,B 종료
>     ↓
>   결과: 노드 1개로 압축 → 비용 절반
> ```
>
> **Disruption (방해) 이란?**
> Karpenter가 의도적으로 노드를 종료하는 동작 통칭. consolidation도 disruption의 한 종류.
> 다른 종류: drift (NodePool 설정 변경 감지), expiration (expireAfter 만료), interruption (Spot 회수).

## 1. 현재 상태 확인 (lab-02 에서 inflate 가 떠 있다고 가정)

```bash
kubectl get nodes -L managed-by
kubectl get pods -l app=inflate
```

## 2. Pod 줄이기

```bash
kubectl scale deploy inflate --replicas=2
```

watch (별도 터미널):
```bash
watch -n2 'kubectl get nodes -L nodepool,managed-by; echo; kubectl get nodeclaims'
```

기대 (30초 후):
- Karpenter 가 빈 노드를 cordon (`SchedulingDisabled`)
- drain 시작 (Pod이 다른 노드로 이전)
- 노드 / NodeClaim 제거
- EC2 인스턴스 종료

> **🧠 Cordon vs Drain**
> - **Cordon**: 노드에 "더 이상 신규 Pod 받지 마" 표시. 기존 Pod은 유지. `SchedulingDisabled` 표기.
> - **Drain**: cordon + 기존 Pod을 다른 노드로 이동 (eviction). PDB 존중.
>
> 회수 순서:
> 1. cordon (신규 차단)
> 2. drain (Pod 이동, 다른 노드에 충분한 공간 있을 때)
> 3. EC2 terminate
> 4. NodeClaim/Node 객체 삭제

`consolidateAfter: 30s` 설정 효과 — 30초 동안 underutilized 상태가 유지되면 회수.

> **`consolidateAfter` 의 역할**
> 잠깐 비었다가 다시 Pod이 들어올 수도 있음 (튕김). 이 시간 동안 안정적으로 비어있을 때만 회수.
> 너무 짧으면 (5초) → 노드 막 만들고 막 죽이는 thrashing.
> 너무 길면 (10분) → 비용 절감 효과 ↓.
> 30초~3분이 적정.

## 3. 모두 0 으로 만들기

```bash
kubectl scale deploy inflate --replicas=0
```

→ Karpenter 노드 모두 회수. 약 1분 후 `kubectl get nodes` 에 기존 워커 노드만 남음.

## 4. consolidationPolicy 비교

### 4.1 WhenEmpty (보수적)
- 노드가 **완전히 빈** 경우만 회수
- 안전하지만 자원 낭비 가능

```bash
kubectl patch nodepool default --type=merge \
  -p '{"spec":{"disruption":{"consolidationPolicy":"WhenEmpty","consolidateAfter":"30s"}}}'
```

> **`kubectl patch --type=merge`**: JSON merge patch. 기존 spec에 일부분만 덮어씀.
> 다른 옵션: `--type=json` (JSON Patch RFC 6902, 더 정밀), `--type=strategic` (K8s 전용 strategic merge).

### 4.2 WhenEmptyOrUnderutilized (권장 / 본 lab 의 기본)
- 노드가 비거나, **사용률이 낮고 다른 노드로 이전 가능**할 때 회수
- 더 적극적인 비용 최적화

```bash
kubectl patch nodepool default --type=merge \
  -p '{"spec":{"disruption":{"consolidationPolicy":"WhenEmptyOrUnderutilized","consolidateAfter":"30s"}}}'
```

> **🧠 두 정책의 운영 트레이드오프**
> | 정책 | 비용 | 안정성 | 권장 |
> |------|------|--------|------|
> | `WhenEmpty` | 절감 ↓ | 매우 안전 (Pod 안 옮김) | DB, stateful |
> | `WhenEmptyOrUnderutilized` | 절감 ↑ | Pod 이동 발생 (PDB로 보호) | 일반 stateless 워크로드 |
>
> 운영에선 워크로드별 NodePool 분리 + 정책 다르게 적용.

## 5. Underutilized Consolidation 시연

작은 Pod 여러 개를 다른 노드에 떠있는 상태로 만든 뒤, 그것을 한 노드로 몰아 정리하는 동작.

```bash
# 작은 Pod 6개 (각 0.2 CPU)
cat > /tmp/small.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: small
spec:
  replicas: 6
  selector: {matchLabels: {app: small}}
  template:
    metadata: {labels: {app: small}}
    spec:
      nodeSelector: {managed-by: karpenter}
      containers:
        - name: pause
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
          resources: {requests: {cpu: 200m, memory: 100Mi}}
EOF
kubectl apply -f /tmp/small.yaml
sleep 60
kubectl get pods -l app=small -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
```

처음에는 여러 노드에 분산. 일정 시간 후 Karpenter 가 통합:
```bash
sleep 120
kubectl get pods -l app=small -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
```

기대: Pod 들이 더 적은 노드 (가능하면 1개) 로 통합되고, 빈 노드는 회수.

> **`uniq -c` 트릭**: 같은 줄을 카운트. 노드별 Pod 수 분포를 한 줄씩 표기.

## 6. PDB (PodDisruptionBudget) 으로 보호

운영에서는 회수 시 동시 다운 Pod 수를 제한:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: small-pdb
spec:
  minAvailable: 50%
  selector:
    matchLabels: {app: small}
```

→ Karpenter 회수 시에도 PDB 존중. 이 lab 에서는 적용하지 않지만 운영 필수.

> **🧠 PDB 의 의미와 동작**
> "이 라벨 가진 Pod 중 동시에 다운될 수 있는 비율/개수 한도".
> Karpenter, kubectl drain, 노드 업그레이드 등 모든 voluntary disruption이 PDB 존중.
>
> ```yaml
> minAvailable: 50%   # 항상 50% 이상 살아있어야 (replicas 4면 항상 2개+)
> # 또는
> maxUnavailable: 1   # 동시에 1개만 다운 가능
> ```
>
> **함정**: PDB가 너무 빡빡하면 (`minAvailable: 100%`) → 노드 회수/업그레이드 영원히 못 함 → 클러스터 마비.
> 운영 권장: `maxUnavailable: 1` (보수적이지만 진행은 됨).

## 7. 정리

```bash
kubectl delete deploy inflate small
kubectl delete -f /tmp/small.yaml --ignore-not-found
```

NodePool / EC2NodeClass 는 다음 모듈에서도 사용하므로 유지.

## 학습 확인 질문

1. `consolidateAfter` 의 시간 의미는 (회수 결정의 cool-down)?
2. PDB 가 `minAvailable: 100%` 이면 Consolidation 가능한가?
3. ON_DEMAND 노드와 Spot 노드를 Karpenter 가 동시에 운영할 수 있나? 어떻게 비율 조정?

> **힌트**:
> 1. 노드가 underutilized/empty 상태로 이 시간 동안 유지되어야 회수 시작. 짧으면 thrashing, 길면 비용 절감 ↓.
> 2. 거의 불가능. 모든 Pod이 살아있어야 → Pod 이동 = 일시 다운 → PDB 위반. Karpenter가 회수 시도하다 실패.
> 3. 가능. NodePool을 두 개 만들고 `karpenter.sh/capacity-type: [spot]` / `[on-demand]` 분리. weight로 우선순위.

다음: [quiz.md](./quiz.md)
