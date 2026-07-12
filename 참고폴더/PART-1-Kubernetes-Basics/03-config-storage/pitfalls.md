# 흔한 함정 5선 — 03. Config & Storage

## 1. ConfigMap 환경변수가 갱신 안 돼서 디버깅에 시간 허비

**증상**: ConfigMap의 값을 수정했는데 앱 동작이 그대로.

**원인**: 환경변수는 Pod 시작 시 한 번만 주입. ConfigMap을 수정해도 Pod 환경변수는 안 바뀜.

**해결**:
```bash
kubectl rollout restart deploy/<name>
```

또는 자동화: ConfigMap 해시를 Pod template의 annotation에 넣어 변경 시 rollout 트리거 (Helm `helm.sh/hook` 또는 stakater/Reloader 등).

---

## 2. PVC가 영영 Pending

**증상**:
```
NAME   STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
data   Pending   ...
```

**원인 후보**:
1. **CSI Driver 미설치** — `kubectl get csidrivers`
2. **CSI Driver의 ServiceAccount IRSA 누락** — Pod 권한 부족으로 EBS API 호출 실패
3. **WaitForFirstConsumer + Pod 미스케줄링** — Pod이 안 떠서 PVC가 대기
4. **availabilityZone 충돌** — 다른 AZ의 EBS 와 매칭 시도

**진단**:
```bash
kubectl describe pvc data | tail -20
kubectl logs -n kube-system -l app=ebs-csi-controller --tail=50
```

`Events:` 의 메시지로 정확한 이유 파악.

---

## 3. PVC 삭제했는데 EBS가 남아 매월 청구

**증상**: AWS Cost Explorer에 "왜 EBS 비용이 계속 나가지?"

**원인**:
- StorageClass의 `reclaimPolicy: Retain` — 의도적으로 데이터 보존
- StatefulSet의 PVC 는 sts 삭제만으론 안 사라짐
- PV가 `Failed` 상태로 남아 정리 안 됨

**진단**:
```bash
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/eks-study,Values=owned" \
  --query 'Volumes[].[VolumeId,State,Tags[?Key==`Name`].Value|[0]]' --output table
```

해결:
```bash
# K8s에서 떨어져 나온 EBS 직접 삭제
aws ec2 delete-volume --volume-id vol-xxx
```

운영 데이터면 신중히. 학습용은 즉시 삭제.

---

## 4. StatefulSet 의 한 Pod이 영영 Ready 안 됨 → 뒤 Pod가 시작 안 됨

**증상**: `redis-0` 이 `0/1 Pending` 또는 `0/1 Running` 에 머물러, `redis-1` 이 시작 안 됨.

**원인**: StatefulSet은 순차 시작 — N번이 Ready여야 N+1번이 시작.

**진단**:
```bash
kubectl describe pod redis-0       # Events / readinessProbe 실패 원인
kubectl logs redis-0
```

흔한 원인:
- readinessProbe 가 너무 빡빡 (앱 워밍업 시간 미고려)
- PVC 바인딩 실패 (위 함정 2 참조)
- 노드 자원 부족 + Pod requests 너무 큼

**임시 우회**: `podManagementPolicy: Parallel` 로 동시 시작 가능 (단 데이터 일관성이 필요한 클러스터에선 비추).

---

## 5. ConfigMap/Secret 의 키 이름과 환경변수 이름 혼동

**증상**: ConfigMap에 `LOG_LEVEL: info` 가 분명히 있는데 `kubectl exec ... env` 에 없음.

**원인 후보**:

a) `envFrom` 아닌 `env: - valueFrom:` 으로 특정 키만 주입했고, 그 키가 ConfigMap의 키 이름과 다름:
```yaml
env:
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: LOGLEVEL    # ← 오타 (실제 키는 LOG_LEVEL)
```

b) `envFrom` 으로 했는데 ConfigMap 키가 환경변수로 못 쓰는 형식 (`-` 포함, 숫자 시작 등) → K8s가 그 키만 무시:
```
warning: Couldn't find key MY-KEY in ConfigMap default/app-config
```

**진단**:
```bash
kubectl describe pod <name> | grep -A20 'Environment:'
kubectl get cm app-config -o yaml
```

키 이름은 `[A-Z_][A-Z0-9_]*` 패턴 권장.
