# 시나리오 6 — 노드 NotReady

> **🌱 노드 NotReady 의미**
> kubelet이 EKS Control Plane에 정기적으로 "나 살아있어요" heartbeat 전송.
> 일정 시간 (기본 40초) 못 받으면 → 노드 NotReady → 그 노드의 Pod들은 Unknown 상태로.
>
> 영향: 그 노드의 모든 Pod 트래픽 못 받음. 신규 Pod 스케줄 X. 5분 후 자동 evict.
>
> 주된 원인: kubelet 죽음, 네트워크 단절, 디스크 가득, 메모리 압박, CNI Pod 죽음.

## 1. 증상 (실제 발생 시)

```bash
kubectl get nodes
```

```
NAME              STATUS     ROLES    AGE   VERSION
ip-10-20-x-x...   NotReady   <none>   1d    v1.30.x
ip-10-20-y-y...   Ready      <none>   1d    v1.30.x
```

## 2. 진단

### 2.1 노드 describe

```bash
kubectl describe node ip-10-20-x-x...
```

`Conditions` 섹션 주목:
```
Type             Status  Reason
Ready            False   KubeletNotReady
MemoryPressure   False
DiskPressure     False
PIDPressure      False
NetworkUnavailable False
```

`Ready: False, Reason: KubeletNotReady` → kubelet 자체 문제.

> **🧠 노드 Conditions 5종**
> | Type | True 의미 |
> |------|----------|
> | `Ready` | 노드 정상 (kubelet heartbeat OK) |
> | `MemoryPressure` | 노드 메모리 부족 (Pod 죽일 수 있음) |
> | `DiskPressure` | 디스크 가득 (이미지 정리 trigger) |
> | `PIDPressure` | 프로세스 ID 가득 (포크 폭탄?) |
> | `NetworkUnavailable` | 네트워크 라우팅 안 됨 |
>
> 이상적: Ready=True, 나머지 모두 False.
> Pressure 가 True면 그 노드는 곧 Pod 추방 시작.

### 2.2 시스템 Pod 상태

```bash
# CNI / kube-proxy
kubectl get pods -n kube-system -o wide --field-selector spec.nodeName=ip-10-20-x-x...
```

만약 `aws-node` (VPC CNI) 가 Pending 또는 CrashLoop 면 → 노드의 네트워크 셋업 실패 → kubelet 이 NotReady 보고.

> **🧠 왜 CNI 죽으면 노드 NotReady?**
> kubelet은 CNI 연결을 통해 Pod 네트워크 셋업.
> CNI가 죽으면 → 새 Pod 만들 수 없음 → kubelet이 자기 노드를 "NotReady"로 보고 (Pod 못 받게).

### 2.3 kubelet 로그 (EC2 콘솔)

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=ip-10-20-x-x..." \
  --query 'Reservations[].Instances[].InstanceId' --output text)

aws ec2 get-console-output --instance-id $INSTANCE_ID --output text | tail -100
```

또는 SSM Session Manager 로 노드에 접근:
```bash
aws ssm start-session --target $INSTANCE_ID
# 안에서:
sudo journalctl -u kubelet -n 200 --no-pager
```

> **🧠 SSM Session Manager**
> SSH 키 없이 IAM 인증으로 EC2 접속. EKS 노드에는 SSM Agent 기본 설치돼 있음 (Karpenter NodeRole에 `AmazonSSMManagedInstanceCore` 정책).
> 운영에선 SSH보다 SSM 권장 (인바운드 22 포트 안 열어도 됨, 모든 세션 CloudTrail 기록).

## 3. 흔한 원인 매핑

| Reason / 메시지 | 원인 |
|-----------------|------|
| `KubeletNotReady` + CNI Pod down | VPC CNI 문제 (IRSA, IP 부족) |
| `disk-pressure` | 노드 디스크 가득 (`/var/lib/containerd` 등) |
| `memory-pressure` | 노드 메모리 가득 |
| `OutOfDisk` | 옛 K8s 의 disk-pressure |
| `NetworkUnavailable` | NAT/Routing 문제 |
| 노드 자체 보임 안 함 (NotReady 30분+) | kubelet stuck → 노드 재기동 권장 |

## 4. 해결 — 자주 쓰는 패턴

### 4.1 Pod 빼내기 (cordon + drain)

```bash
kubectl cordon ip-10-20-x-x...
kubectl drain ip-10-20-x-x... --ignore-daemonsets --delete-emptydir-data
```

→ 정상 노드로 Pod 들이 옮겨짐.

> **🧠 cordon + drain 동작**
> - **cordon**: 노드에 "신규 Pod 받지 마" 표시. 기존 Pod 유지. STATUS 컬럼에 `SchedulingDisabled` 표시.
> - **drain**: cordon + 기존 Pod evict (다른 노드로 이동). PDB 존중.
>
> **`--ignore-daemonsets`**: DaemonSet은 노드별 1개라 다른 노드로 옮길 수 없음. drain 무시 옵션.
> **`--delete-emptydir-data`**: emptyDir 볼륨 데이터 손실 OK 동의 (옮기면 데이터 사라지므로).
>
> 이 둘 안 붙이면 drain이 거부됨 (안전을 위해).

### 4.2 노드 종료 후 재생성

Managed Node Group 의 경우 인스턴스 종료 → ASG 가 새 인스턴스 자동 생성:
```bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
```

Karpenter 가 만든 노드:
```bash
kubectl delete nodeclaim <claim-name>
```

> **`kubectl delete nodeclaim`** 이 더 좋은 이유: Karpenter가 cordon/drain → 새 노드 띄움 → 옛 노드 종료 의 표준 흐름.
> EC2 직접 terminate 하면 graceful 안 됨.

### 4.3 디스크 가득 시

`/var/lib/docker` 또는 `/var/lib/containerd` 가 가득. 이미지 정리:
```bash
# 노드 SSH 후
sudo crictl rmi --prune
```

또는 `imageGCHighThresholdPercent` 를 kubelet config 에 낮게 설정 (자동 정리 트리거 빠르게).

> **🧠 kubelet의 자동 이미지 GC**
> - `imageGCHighThresholdPercent` (기본 85%) 도달 → 이미지 정리 시작
> - `imageGCLowThresholdPercent` (기본 80%) 까지 정리
> - 안 쓰는 이미지부터 (LRU)
>
> 이미지 큰 앱이 많으면 노드 디스크 30Gi 부족할 수 있음 → 50Gi+ 권장.

## 5. 예방

- 모니터링: CloudWatch / Prometheus 의 노드 health (NotReady 알람)
- Karpenter 의 `expireAfter` 로 주기적 노드 회전
- 노드 디스크 사이즈 충분히 (gp3 30Gi 이상)

> **🧠 `expireAfter` 의 역할**
> Karpenter 노드를 N시간 후 자동 종료 (새 노드로 교체).
> 운영 효과:
> - 옛 AMI/커널 누적 막음 (보안 패치 강제 적용)
> - 메모리 leak 누적 방지 (재기동으로 클린)
> - 매번 검증된 부팅 흐름

## 학습 확인

- `kubectl drain` 의 `--ignore-daemonsets` 가 필요한 이유는?
- DaemonSet Pod 는 drain 으로 못 내보낸다. 그럼 어떻게 정리?
- 노드가 NotReady 인 동안 그 노드의 Pod 들의 `STATUS` 는?

> **힌트**:
> - DaemonSet은 노드별 1개라 다른 노드로 옮길 수 없음. drain이 거부 → `--ignore-daemonsets` 으로 "DaemonSet은 그냥 두고 나머지만 옮겨" 지시.
> - 노드 자체를 종료하면 자동 정리. 또는 DaemonSet 자체를 nodeAffinity로 그 노드 회피하게 패치.
> - 5분(`tolerations.tolerationSeconds: 300` 기본) 까지 Running. 그 후 NotReady taint 만나서 evict → Terminating → 다른 노드에 새 Pod.
