# 시나리오 7 — PVC stuck Pending

> **🌱 PVC가 Pending 인 이유들**
> PVC 생성 → 어떤 PV에 바인딩될지 결정 → Bound. 이 흐름 어디든 막힐 수 있음.
>
> 1. **StorageClass 없음**: 동적 프로비저닝 불가
> 2. **CSI 드라이버 권한 부족**: EBS 만들 권한 없음
> 3. **WaitForFirstConsumer + Pod Pending**: chicken-and-egg
> 4. **AZ 미스매치**: PV는 a-AZ인데 Pod이 c-AZ로
> 5. **용량 부족**: AWS 계정의 EBS quota 도달

## 1. 재현

존재하지 않는 StorageClass 로 PVC 만들기:
```bash
cat > /tmp/bad-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bad-pvc
spec:
  storageClassName: nonexistent-sc
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF
kubectl apply -f /tmp/bad-pvc.yaml
sleep 10
```

## 2. 증상

```bash
kubectl get pvc bad-pvc
```

```
NAME      STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
bad-pvc   Pending   ...                                 nonexistent-sc
```

> **PVC 상태**:
> - `Pending`: 아직 PV 못 찾음/못 만듦
> - `Bound`: PV에 바인딩됨 (사용 가능)
> - `Lost`: 바인딩된 PV가 사라짐 (드물게 발생)

## 3. 진단

### 3.1 PVC describe

```bash
kubectl describe pvc bad-pvc
```

기대 (Events):
```
storageclass.storage.k8s.io "nonexistent-sc" not found
```

> **describe의 Events** 가 PVC 트러블슈팅의 핵심. 어떤 단계에서 막혔는지 명시.

### 3.2 사용 가능한 StorageClass 확인

```bash
kubectl get sc
```

기대:
```
NAME           PROVISIONER             RECLAIMPOLICY   ...
gp3 (default)  ebs.csi.aws.com         Delete          ...
gp2            kubernetes.io/aws-ebs   Delete          ...
```

> **🧠 컬럼 의미**
> | 컬럼 | 의미 |
> |------|------|
> | `(default)` | PVC가 storageClassName 안 적으면 이 SC 사용 |
> | `PROVISIONER` | 어느 CSI 드라이버가 처리? `ebs.csi.aws.com` (신) vs `kubernetes.io/aws-ebs` (구, deprecated) |
> | `RECLAIMPOLICY` | PVC 삭제 시 EBS 어떻게? `Delete` (삭제) / `Retain` (보존) |

### 3.3 다른 흔한 원인

| Events 메시지 | 원인 |
|---------------|------|
| `storageclass not found` | StorageClass 오타 / 미설치 |
| `waiting for first consumer` | Pod이 PVC 를 마운트해야 PV 가 만들어짐 (정상, 혹은 Pod Pending) |
| `failed to provision volume: ... AccessDenied` | EBS CSI Driver 의 IRSA 권한 부족 |
| `volume node affinity conflict` | PV 가 다른 AZ 에 있어 Pod 노드와 매칭 안 됨 |

## 4. 해결

```bash
# StorageClass 수정
kubectl patch pvc bad-pvc --type=merge -p '{"spec":{"storageClassName":"gp3"}}'
# 안 됨: spec 의 일부는 immutable

# 깔끔한 방법: PVC 삭제 후 재생성
kubectl delete pvc bad-pvc
sed 's/nonexistent-sc/gp3/' /tmp/bad-pvc.yaml | kubectl apply -f -
sleep 10
kubectl get pvc bad-pvc
```

기대: `Bound`.

> **🧠 PVC spec 의 immutable 필드**
> 한번 만든 PVC의 storageClassName, accessModes, volumeName 등은 수정 불가.
> 이유: 이미 PV에 바인딩됐을 수도 있어 변경 시 일관성 깨짐.
>
> 변경 가능한 것: `spec.resources.requests.storage` (확장만, 축소 X). EBS는 온라인 확장 가능.

## 5. EBS CSI IRSA 문제 진단

PVC 가 만들어졌는데 EBS 자체가 안 생기면:
```bash
kubectl logs -n kube-system -l app=ebs-csi-controller -c csi-provisioner --tail=30
```

`AccessDenied` 면 IRSA 점검:
```bash
kubectl get sa -n kube-system ebs-csi-controller-sa -o yaml | yq '.metadata.annotations'
```

> **🧠 EBS CSI Controller 의 컨테이너 6종**
> EBS CSI Pod엔 컨테이너가 여러 개 (sidecar 패턴):
> - `ebs-plugin`: 메인 (AWS API 호출)
> - `csi-provisioner`: PVC watch + 동적 프로비저닝
> - `csi-attacher`: PV를 노드에 attach
> - `csi-resizer`: 볼륨 확장
> - `csi-snapshotter`: 스냅샷 관리
> - `liveness-probe`: 헬스체크
>
> 로그 볼 땐 `-c <container>` 로 어느 컨테이너인지 명시.

## 6. WaitForFirstConsumer 시 Pod Pending 과 PVC Pending 의 chicken-and-egg

```bash
# PVC + Pod 함께
cat > /tmp/wait-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: wait-data}
spec:
  storageClassName: gp3
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: wait-pod}
spec:
  nodeSelector: {bogus: bogus}      # 매칭 노드 없음 → Pod Pending
  containers:
    - name: c
      image: alpine
      command: ["sleep","3600"]
      volumeMounts: [{name: data, mountPath: /data}]
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: wait-data}
EOF
kubectl apply -f /tmp/wait-pvc.yaml
sleep 15
kubectl get pvc wait-data
kubectl describe pod wait-pod | tail -10
```

기대:
- Pod: `FailedScheduling` (nodeSelector 미매칭)
- PVC: `Pending` — `waiting for first consumer` (Pod이 안 떠서)

→ Pod 의 진짜 문제 해결해야 PVC 도 풀림.

> **🧠 WaitForFirstConsumer 의 의도**
> EBS는 단일 AZ 종속. PVC 만든 즉시 EBS 만들면 → 어느 AZ에 만들지 정해야 함 → Pod이 다른 AZ로 가면 마운트 불가.
>
> WaitForFirstConsumer 는:
> 1. PVC 만들어도 PV 안 만듦 (대기)
> 2. 사용자 Pod이 PVC 마운트 시도 → 스케줄러가 노드 결정
> 3. 그 노드의 AZ 알아냄 → 그 AZ에 EBS 생성
> 4. Pod이 그 노드에 정상 스케줄
>
> 이걸 안 하고 `Immediate` 면 → AZ 운 좋아야 동작. 운영엔 절대 권장 X.

```bash
kubectl delete -f /tmp/wait-pvc.yaml
```

## 7. 정리

```bash
kubectl delete pvc bad-pvc --ignore-not-found
```

## 학습 확인

- `WaitForFirstConsumer` 모드의 의도는?
- PV 의 `nodeAffinity` 와 Pod 의 위치가 안 맞으면 어떤 메시지?
- EBS CSI IRSA 의 K8s SA 이름은?

> **힌트**:
> - Pod이 어느 노드에 갈지 정해진 후 EBS 만듦 → 그 노드의 AZ에 EBS 생성. AZ 미스매치 방지.
> - `volume node affinity conflict` 또는 `0/N nodes are available: N node(s) had volume node affinity conflict`. EBS는 단일 AZ 종속.
> - `kube-system` 네임스페이스의 `ebs-csi-controller-sa` (Controller). 노드 측 DaemonSet은 `ebs-csi-node-sa`.
