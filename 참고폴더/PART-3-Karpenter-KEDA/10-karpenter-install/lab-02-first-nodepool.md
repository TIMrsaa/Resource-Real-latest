# Lab 02 — 첫 NodePool + 자동 노드 추가 시연

## 학습 확인 포인트

- [ ] NodePool/EC2NodeClass 적용 후 Karpenter 가 인식
- [ ] Pending Pod 발생 → Karpenter 가 노드 추가 → Pod 스케줄
- [ ] NodeClaim 객체로 노드 생성 진행 추적

> **🌱 이번 lab 의 핵심 흐름**
> ```
>   사용자: kubectl scale deploy --replicas=5
>     ↓
>   K8s scheduler: Pod 5개 → 노드 자원 부족 → Pending
>     ↓ (Karpenter watch)
>   Karpenter: "이 Pod들에게 가장 효율적인 EC2는?"
>     ↓ NodeClaim 생성
>   AWS EC2 API: RunInstances → 노드 부팅
>     ↓ ~30~60초
>   kubelet join → Node Ready → Pod 스케줄됨
> ```
>
> **NodeClaim** 이란? Karpenter가 EC2 1대를 만들기 위해 만드는 임시 객체.
> "이런 요구사항의 인스턴스 1개" 라는 진행 추적 마커. 노드 Ready 되면 NodeClaim도 Ready.

## 1. NodePool + EC2NodeClass 적용

```bash
kubectl apply -f manifests/nodepool-default.yaml
kubectl get nodepool,ec2nodeclass
```

기대:
```
NAME                              NODECLASS   NODES   READY   AGE
nodepool.karpenter.sh/default     default     0       True    10s

NAME                                       READY   AGE
ec2nodeclass.karpenter.k8s.aws/default     True    10s
```

> **`READY: True` 의미**: EC2NodeClass가 검증 통과 (서브넷/SG/AMI 모두 발견됨).
> NodePool은 EC2NodeClass 참조 + 기본 검증.

`READY: True` 가 안 되면 EC2NodeClass 의 `status.conditions` 확인:
```bash
kubectl describe ec2nodeclass default
```

흔한 원인: 서브넷/SG 태깅 누락 → status에 명시.

> **`status.conditions` 보는 법**
> ```yaml
> status:
>   conditions:
>     - type: Ready
>       status: "False"
>       message: "no subnets found matching ..."   ← 여기 원인
> ```

## 2. Watch 준비 (별도 터미널 3개)

터미널 A — 노드 변화:
```bash
watch -n2 kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```

> **노드의 자동 라벨**: Karpenter는 만든 노드에 자동으로 라벨 부착.
> - `karpenter.sh/nodepool` = 어느 NodePool 소속
> - `karpenter.sh/capacity-type` = spot 또는 on-demand
> - `node.kubernetes.io/instance-type` = 실제 인스턴스 타입 (c5.large 등)
> -L 로 컬럼 표시하면 변화 추적 쉬움.

터미널 B — Karpenter 로그:
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

터미널 C — NodeClaim:
```bash
watch -n2 kubectl get nodeclaims
```

## 3. inflate Deployment 적용 (replicas=0)

```bash
kubectl apply -f manifests/inflate-deployment.yaml
kubectl get deploy inflate
```

> **`replicas: 0` 으로 시작하는 이유**: 시연용. 즉시 띄우면 변화 못 봄. 단계별로 scale 명령 칠 거라.

## 4. 스케일 업 → 노드 자동 추가

```bash
kubectl scale deploy inflate --replicas=5
kubectl get pods -l app=inflate
```

→ 즉시 5개 Pod 모두 Pending (요청 자원이 큼 + nodeSelector 가 Karpenter 노드 만 매칭).

> **🧠 왜 Pending? 두 가지 원인**
> 1. inflate Deployment의 Pod이 `cpu: 1` + `memory: 1.5Gi` 요청 → 일반 노드(t3.medium 4Gi) 한 대당 1~2개 한계
> 2. nodeSelector `managed-by: karpenter` → 기존 워커 노드(라벨 없음) 매칭 안 됨
>
> 둘 다 만족하는 노드가 없으니 Karpenter가 새로 만들어야.

터미널 A 에서 1~2분 후:
```
NAME                                              STATUS   ...   NODEPOOL    CAPACITY-TYPE
ip-10-20-x-x.ap-northeast-2.compute.internal     Ready    ...   <none>      ON_DEMAND        ← 기존 워커
ip-10-20-y-y.ap-northeast-2.compute.internal     Ready    ...   default     spot             ← Karpenter 가 추가!
```

터미널 B 의 Karpenter 로그:
```
INFO  computed new nodeclaim(s) to fit pod(s)
INFO  registered nodeclaim
INFO  initialized nodeclaim
INFO  inflate-xxx, ... scheduled
```

> **🧠 Karpenter 노드 생성 단계**
> ```
>   Pod Pending 감지
>     ↓
>   computed new nodeclaim(s)    ← 어떤 EC2 띄울지 결정 (인스턴스 타입 선택)
>     ↓
>   registered nodeclaim         ← K8s에 NodeClaim 객체 생성
>     ↓
>   AWS EC2 RunInstances 호출
>     ↓ EC2 부팅 (~30s)
>   initialized nodeclaim        ← 노드가 클러스터 join + Ready
>     ↓
>   Pod 스케줄링 (kubelet에 의해)
> ```

터미널 C:
```
NAME             TYPE         CAPACITY  ZONE              NODE                 READY   AGE
default-abcde    c5.large     spot      ap-northeast-2a   ip-10-20-y-y...     True    1m
```

## 5. Pod 들이 스케줄되었는지 확인

```bash
kubectl get pods -l app=inflate -o wide
```

기대: 모든 Pod 가 Running, Karpenter 노드에 떠 있음.

## 6. 더 늘려보기

```bash
kubectl scale deploy inflate --replicas=15
```

기대: 추가 노드 1~2 대 더 자동 생성. 인스턴스 타입은 Karpenter 가 비용/가용성 보고 선택 (c5.large / m5.large / m6a.large 등).

> **🧠 Karpenter의 인스턴스 선택 로직**
> NodePool requirements 안에서 가능한 모든 인스턴스 타입을 후보로 두고:
> 1. Pod의 자원 합 vs 인스턴스 자원 → bin packing 효율 계산
> 2. 후보별 시간당 비용 (Spot price API 조회)
> 3. 가장 저렴한 + Pod이 다 들어가는 인스턴스 선택
> = 동일한 NodePool에 매번 다른 인스턴스 타입 떠도 정상.

## 7. NodePool 의 limits 효과

```bash
kubectl describe nodepool default | grep -A3 'Limits\|Resources:'
```

`spec.limits.cpu: 100` 까지만 만듦. 그 이상 요청은 Pending 유지 (제한이 보호 장치).

> **🧠 limits의 의미 (안전장치)**
> "이 NodePool 전체로 만들 수 있는 자원 총합".
> 버그/공격으로 Pod이 무한 늘어나도 → 100 vCPU 도달하면 Karpenter가 더 안 만듦 → 비용 폭주 차단.
>
> 실무에서 절대 빠뜨리면 안 되는 설정. 학습 환경엔 더 작게 (예: 30) 도 OK.

## 8. 확인 명령 모음

```bash
# 현재 NodeClaims
kubectl get nodeclaims -o custom-columns=NAME:.metadata.name,TYPE:.spec.requirements,READY:.status.conditions[?(@.type=='Ready')].status

# Pod 분포
kubectl get pods -l app=inflate -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' | column -t

# Karpenter 가 만든 EC2 인스턴스
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=default" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,InstanceLifecycle,LaunchTime]' \
  --output table
```

> **`InstanceLifecycle`** 컬럼: `spot` 또는 빈 값(=on-demand). NodePool 설정대로 spot이 떠야.

## 학습 확인 질문

1. NodeClaim 이 Ready 가 되기까지 어떤 단계를 거치는가?
2. NodePool 의 `limits.cpu: 100` 이 의미하는 것은?
3. Pod 의 nodeSelector 가 NodePool 의 라벨과 안 맞으면 어떻게 되는가?

> **힌트**:
> 1. computed → registered (NodeClaim 생성) → EC2 RunInstances → 부팅 → kubelet join → initialized (Ready).
> 2. 이 NodePool 으로 만들 수 있는 EC2의 vCPU 총합 한도. 도달하면 새 노드 안 만듦 (=비용 안전장치).
> 3. Karpenter가 nodeSelector 라벨도 NodePool labels와 매칭 시도. 안 맞으면 다른 NodePool 시도. 모든 NodePool에서 매칭 실패 → Pod Pending 유지.

다음: [lab-03-consolidation.md](./lab-03-consolidation.md)
