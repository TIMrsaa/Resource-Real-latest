# 시나리오 3 — Pod Pending

> **🌱 Pending 이 뭐고 왜?**
> Pod 만들어졌지만 **아직 어느 노드에도 배치 안 됨** = `Pending`.
> 스케줄러가 결정 못 하는 이유:
> 1. 노드 자원 부족 (CPU/메모리)
> 2. 라벨/affinity 조건 매칭 실패
> 3. taint 견딜 toleration 없음
> 4. PVC 바인딩 실패
> 5. Pod IP 한도 도달 (VPC CNI)
>
> 모두 `kubectl describe pod` 의 Events 섹션에 명시됨.

## 1. 재현

지나치게 큰 자원 요청 (`kubectl run --requests` 플래그는 1.25에서 제거되어 매니페스트로 대체):
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: hog
spec:
  containers:
  - name: hog
    image: nginx
    resources:
      requests:
        cpu: "100"
        memory: 100Gi
EOF
sleep 15
```

> **requests `cpu: "100"` / `memory: 100Gi`**: 100 vCPU + 100GiB 메모리 요청. 학습 클러스터(t3.medium=2vCPU/4GiB)에서 절대 불가.

## 2. 증상

```bash
kubectl get pod hog
```

```
NAME   READY   STATUS    RESTARTS   AGE
hog    0/1     Pending   0          15s
```

## 3. 진단

```bash
kubectl describe pod hog | tail -15
```

기대 (Events):
```
FailedScheduling: 0/3 nodes are available: 3 Insufficient cpu, 3 Insufficient memory
```

> **🧠 메시지 읽는 법**
> `0/3 nodes are available` = 3개 노드 중 0개가 사용 가능.
> `: 3 Insufficient cpu, 3 Insufficient memory` = 3개 노드 모두 CPU/메모리 부족.
>
> 노드별 다른 이유면:
> ```
> 0/3 nodes are available: 1 Insufficient cpu, 2 had untolerated taint
> ```
> = 1개는 CPU 부족, 2개는 taint 견딜 toleration 없음.

## 4. 원인 매핑

| Events 메시지 | 원인 |
|---------------|------|
| `Insufficient cpu/memory` | 노드 자원 부족 (또는 requests 과다) |
| `node(s) didn't match Pod's node affinity` | nodeSelector / affinity 매칭 실패 |
| `Too many pods` | 노드의 Pod 한계 (VPC CNI IP 한계) |
| `had untolerated taint` | taint 에 toleration 없음 |
| `pvc ... not found` | PVC 가 존재 안 함 (또는 PV 바인딩 실패) |
| `node(s) had volume node affinity conflict` | EBS는 AZ 종속. Pod이 다른 AZ로 가려 함 |

> **🧠 가장 헷갈리는 두 메시지**
> - `Too many pods`: 노드의 max-pods 한도 (인스턴스 타입별. t3.medium=17). VPC CNI IP 한도가 원인.
>   → 해결: prefix delegation 활성화 (Part-2-06 lab-01) 또는 더 큰 인스턴스
> - `volume node affinity conflict`: PVC가 ap-northeast-2a 의 EBS인데 Pod가 2c 노드로 스케줄 시도.
>   → 해결: StorageClass의 `volumeBindingMode: WaitForFirstConsumer` (Pod 노드 결정 후 EBS 생성)

## 5. 진단 추가 명령

```bash
# 클러스터 전체 자원 vs 사용
kubectl describe nodes | grep -A5 'Allocated resources:'

# 노드별 라벨
kubectl get nodes --show-labels

# PV/PVC 상태
kubectl get pv,pvc -A
```

> **🧠 `Allocated resources` vs `Capacity`**
> - **Capacity**: 노드의 이론 최대 (4Gi 메모리, 17 pods 등)
> - **Allocatable**: 실제 사용 가능 (시스템 예약 제외 = capacity - kube-reserved - system-reserved)
> - **Allocated**: 현재 Pod requests 합계
>
> 스케줄러는 Allocatable 기준으로 결정. Allocatable이 가득 차면 Pending.
>
> ```bash
> kubectl describe node <NODE> | grep -A5 'Allocated resources'
> # CPU Requests: 1500m / 2000m (75%)
> # Memory Requests: 3Gi / 3.5Gi (85%)
> ```

## 6. 해결

```bash
kubectl delete pod hog
```

운영에선:
- requests 줄이기 (실제 측정값 기반)
- Karpenter / 노드 그룹 capacity 늘리기
- nodeSelector 조정

> **🧠 requests vs limits 의 스케줄링 의미**
> - **requests**: 스케줄링에 사용. "이만큼 보장돼야 띄움". 노드의 Allocatable에서 차감.
> - **limits**: 스케줄링 무관. 런타임에 cgroup으로 강제 (CPU throttle / 메모리 OOMKill).
>
> 스케줄러 트릭: requests를 작게 → 더 많이 띄울 수 있음 (overcommit). 단 노드 압박 시 위험.

## 7. Karpenter 가 떠있다면 어떻게 다른가

Karpenter 가 있으면 `Insufficient cpu` 에 대해 자동으로 노드 추가 시도. 그래도 NodePool 의 `limits` 또는 EC2 SVQ (Service Quota) 한계에 걸리면 Pending 유지. Karpenter 컨트롤러 로그 확인:

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 \
  | grep -i 'unschedulable\|insufficient\|error'
```

> **🧠 Karpenter 가 Pending Pod 보고도 노드 안 만드는 케이스**
> 1. **NodePool의 requirements 와 Pod의 nodeSelector/affinity 불일치** → 어떤 노드도 만들 수 없음
> 2. **NodePool의 `limits` 도달** → 안전장치 발동
> 3. **EC2 Service Quota 도달** (계정의 vCPU 한도) → AWS 콘솔에서 quota 증가 신청
> 4. **Spot capacity 부족** → 잠시 후 재시도 (다른 인스턴스 타입 시도)

## 학습 확인

- requests 와 limits 중 스케줄링에 사용되는 것은?
- 노드 자원이 충분한데도 Pending 인 케이스는?
- VPC CNI 의 Pod IP 한계로 Pending 인지 어떻게 알 수 있나?

> **힌트**:
> - **requests** 만. limits는 런타임에만 적용.
> - taint 미스매치, nodeSelector/affinity 안 맞음, PVC 바인딩 안 됨, Pod IP 한도 도달, volume node affinity conflict.
> - `kubectl describe pod` Events에 `Too many pods` 메시지. `kubectl describe node` 의 Allocated pods 가 Allocatable에 도달했나 확인.
