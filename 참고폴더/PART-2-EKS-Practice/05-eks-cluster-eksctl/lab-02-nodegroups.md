# Lab 02 — 노드 그룹 추가/삭제, 스케일링

## 학습 확인 포인트

- [ ] 두 번째 노드 그룹을 추가해 봤다 (다른 인스턴스 타입)
- [ ] 노드 그룹별 라벨/taint 사용
- [ ] 노드 그룹 스케일 (manual)

> **🌱 이 lab에서 배우는 핵심 개념 미리보기**
> - **Node Group**: 같은 설정(인스턴스 타입, AMI 등)을 가진 노드들의 묶음. ASG로 동작
> - **Label**: 노드/Pod에 붙이는 키-값. 검색·매칭에 사용
> - **nodeSelector**: Pod가 "이 라벨 가진 노드만 가고 싶다" 라고 선언
> - **Taint**: 노드에 붙이는 "이 노드엔 아무 Pod나 오지 마" 표식
> - **Toleration**: Pod에 붙이는 "나는 그 Taint를 견딜 수 있어" 허가증

## 1. 현재 노드 그룹 확인

```bash
eksctl get nodegroup --cluster eks-study --region ap-northeast-2
kubectl get nodes -L workload-type
```

> **`-L workload-type`** 은 "workload-type 라벨 값을 컬럼으로 추가해줘" 라는 옵션.
> `-l` (소문자) 는 필터링, `-L` (대문자) 는 컬럼 표시. 자주 헷갈림.

기대:
```
NAME      WORKLOAD-TYPE
ip-10-20-x-x   general
ip-10-20-y-y   general
```

(ClusterConfig에서 `labels: workload-type: general` 정의)

> **💡 노드 라벨이 어디서 왔나?**
> Lab 01에서 만든 cluster.yaml의 `managedNodeGroups[0].labels` 가 자동으로 노드에 붙은 것.
> eksctl이 노드 부팅 시 kubelet에 `--node-labels=workload-type=general` 인자를 전달.

## 2. 라벨로 Pod 배치 강제

```bash
kubectl run pinned --image=nginx --overrides='{
  "spec": {
    "nodeSelector": {"workload-type": "general"}
  }
}'
kubectl get pod pinned -o wide
```

> **🧠 nodeSelector 란?**
> Pod의 spec에 적는 가장 단순한 노드 선택 방법. "라벨 X=Y 가 있는 노드에만 띄워줘" 라는 요청.
> ```
>   Pod.spec.nodeSelector = { workload-type: general }
>          ↓ 스케줄러가 매칭
>   Node.metadata.labels = { workload-type: general, ... }
> ```
> 매칭 안 되면 Pod는 영원히 `Pending` 상태 (스케줄링 실패).
>
> **더 강력한 옵션**: `nodeAffinity` (regex, preferred/required 등) — 이번 lab은 단순한 nodeSelector만.
>
> **`--overrides` 트릭**: `kubectl run` 으로 빠르게 Pod 만들 때 spec을 부분적으로 덮어씀. YAML 파일 안 만들고 한 줄로 가능.

매칭되는 노드에 떠 있는지 확인 후 정리:
```bash
kubectl delete pod pinned
```

## 3. 두 번째 노드 그룹 추가 (CPU-intensive)

```bash
cat > /tmp/ng-cpu.yaml <<'EOF'
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: eks-study
  region: ap-northeast-2

managedNodeGroups:
  - name: cpu-workers
    # Spot 다양화: 동일 스펙(2 vCPU / 4 GiB)의 현 세대 + 직전 세대를 함께 사용
    # 4종 이상이면 한 풀이 회수돼도 다른 풀로 빠르게 대체 가능
    instanceTypes:
      - c7i.large    # Intel 4세대 (current gen, 권장)
      - c7a.large    # AMD 4세대 EPYC (current gen)
      - c6i.large    # Intel 3세대 (fallback)
      - c6a.large    # AMD 3세대 (fallback)
    spot: true
    desiredCapacity: 1
    minSize: 0
    maxSize: 3
    volumeSize: 30
    volumeType: gp3
    privateNetworking: true
    labels:
      workload-type: cpu
    taints:
      - key: workload
        value: cpu
        effect: NoSchedule
EOF

eksctl create nodegroup -f /tmp/ng-cpu.yaml
```

소요: 약 5분.

> **🧠 왜 노드 그룹을 여러 개 분리하는가?**
> - **인스턴스 타입 분리**: 일반 워크로드(t3.medium) / CPU 집약(c7i.large) / GPU(g6.xlarge)
> - **자원 격리**: "이 GPU 노드는 ML 팀만, 일반 Pod이 침범 못 하게"
> - **Spot/On-Demand 분리**: stateful은 OD, batch는 Spot
> - **AZ 분리**: 특정 AZ에만 띄울 워크로드 (지연 민감)
>
> **🧠 Taint 의 정체 (이게 이번 lab의 핵심)**
> 라벨/nodeSelector 만으로는 약점이 있음:
> ```
>   Pod A: nodeSelector "workload-type=general" → 일반 노드만 감 ✅
>   Pod B: nodeSelector 미지정              → 어디든 감... CPU 노드에도 갈 수 있음 ❌
> ```
> 즉 라벨은 "원하는 곳" 만 강제 가능. "원치 않는 Pod 배제"는 못 함.
>
> Taint는 그 반대: **노드 쪽에서 "오지 마" 라고 거부**.
> ```
>   Node에 taint = workload=cpu:NoSchedule
>      → 이 노드는 toleration 없는 모든 Pod를 거부 (NoSchedule)
>   Pod에 toleration = workload=cpu:NoSchedule
>      → "나는 그 taint OK" 라고 선언한 Pod만 받아줌
> ```
>
> **effect 3종**:
> | effect | 의미 |
> |--------|------|
> | `NoSchedule` | toleration 없는 Pod의 신규 스케줄 거부 (이미 떠있는 Pod는 둠) |
> | `PreferNoSchedule` | 가급적 안 받음 (강제 X, 부드러운 회피) |
> | `NoExecute` | 신규 거부 + 기존 Pod도 추방 (즉시 또는 tolerationSeconds 후) |
>
> **실생활 비유**: VIP 라운지 입구의 "VIP 카드 소지자만" 표지판이 taint, 손님의 VIP 카드가 toleration.

## 4. taint 효과 확인

```bash
kubectl run general-pod --image=nginx
kubectl get pod general-pod -o wide
```

기대: `general` 노드에만 떠 있음 (taint 없음). `cpu` 노드는 taint 때문에 회피.

> **🔍 taint 직접 보기**:
> ```bash
> kubectl describe node <cpu 노드 이름> | grep -A1 Taints
> # Taints: workload=cpu:NoSchedule
> ```
> 또는 한 줄로:
> ```bash
> kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'
> ```

## 5. toleration + nodeSelector 로 cpu 노드에 배치

```bash
cat > /tmp/cpu-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cpu-pod
spec:
  nodeSelector:
    workload-type: cpu
  tolerations:
    - key: workload
      operator: Equal
      value: cpu
      effect: NoSchedule
  containers:
    - name: nginx
      image: nginx
EOF
kubectl apply -f /tmp/cpu-pod.yaml
kubectl get pod cpu-pod -o wide
```

기대: `cpu-workers` 노드에 떠 있음.

> **🧠 왜 nodeSelector + toleration 둘 다 써야 하나?**
> - `toleration` 만 있으면? → "cpu 노드에 가도 됨" 일 뿐. 일반 노드에도 갈 수 있음
> - `nodeSelector` 만 있으면? → "cpu 라벨 가진 노드 가고 싶음" 이지만 taint에 걸려 거부됨 (Pending)
> - **둘 다 있어야** "cpu 노드에 가야하고, taint도 견딜 수 있다" = 정확히 cpu 노드에 떨어짐
>
> **`operator` 종류**:
> - `Equal` : key=value 정확히 일치 (이 예시)
> - `Exists` : key 존재 여부만 (value 무시. 모든 taint 견디는 만능 toleration 가능)
>
> **DaemonSet의 특별 케이스**: 모든 노드에 떠야하는 워크로드(로그 수집기 등)는 보통 모든 taint를 tolerate 하도록 설정.

```bash
kubectl delete pod general-pod cpu-pod
```

## 6. 스케일

```bash
eksctl scale nodegroup --cluster eks-study --name workers --nodes 3
kubectl get nodes -L workload-type
```

기대: general 노드 3개로 증가.

> **🧠 어떤 식으로 스케일이 일어나나?**
> 1. eksctl이 ASG(Auto Scaling Group)의 desired_capacity를 3으로 변경
> 2. ASG가 EC2 1대 신규 띄움 (~1분)
> 3. 노드 부팅 후 kubelet이 EKS Control Plane에 Join
> 4. `kubectl get nodes` 에 새 노드가 Ready 상태로 등장
>
> **수동 스케일 vs 자동 스케일**:
> - 수동 (이번 lab): 사람이 명령어로
> - 자동: Cluster Autoscaler 또는 **Karpenter** (Part 3에서)
>   → "Pending Pod 생기면 알아서 노드 추가"

다시:
```bash
eksctl scale nodegroup --cluster eks-study --name workers --nodes 2
```

> **줄일 때 어떤 노드부터 죽는가?** ASG 기본 정책은 가장 오래된 또는 가장 비어있는 노드.
> Pod가 도는 노드를 죽이면 K8s가 다른 노드로 옮겨주지만 (rescheduling), 잠깐 가용성 ↓.
> → 운영에선 PodDisruptionBudget(PDB)으로 동시에 죽는 Pod 수 제한 권장.

## 7. 노드 그룹 삭제 (cpu-workers는 더 이상 필요 없으므로)

```bash
eksctl delete nodegroup --cluster eks-study --name cpu-workers --region ap-northeast-2 --wait
```

> **`--wait` 플래그**: 삭제 완료까지 명령어 블로킹. 없으면 비동기로 끝남.
>
> **삭제 시 일어나는 일** (eksctl이 자동 처리):
> 1. 노드들 cordon (신규 Pod 배치 차단) → drain (기존 Pod 다른 노드로 이동)
> 2. ASG desired_capacity = 0
> 3. EC2 인스턴스 종료
> 4. CloudFormation 스택 삭제
> 5. K8s API에서 노드 객체 제거

## 학습 확인 질문

1. 노드 그룹별 IAM Role 이 분리되는 이유는? (보안 관점)
2. `spot: true` 인 노드 그룹의 Pod이 갑자기 종료될 때 어떻게 대응할 수 있을까?
3. taint와 toleration 만으로 Pod 배치를 강제할 수 있을까? nodeSelector도 같이 써야 하나?

> **힌트**:
> 1. 노드의 IAM 권한 = 그 노드의 모든 Pod의 권한 (IRSA 미사용 시). 분리 = 최소 권한.
> 2. AWS가 회수 2분 전 알림 → 노드를 cordon → Pod를 다른 노드로 옮길 시간 확보. Karpenter가 자동화.
> 3. taint/toleration은 "갈 수 있음" 만 표현. "정확히 거기로 가라" 는 nodeSelector/affinity가 필요.

다음: [lab-03-addons.md](./lab-03-addons.md)
