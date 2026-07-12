# Lab 02 — EBS 동적 프로비저닝과 데이터 생존 검증

## Step 1. EBS CSI 드라이버 설치 (EKS 관리형 애드온 + Pod Identity)

```bash
# ① Pod Identity 에이전트 애드온 (CSI 드라이버에 IAM 권한을 주는 현대적 방식)
eksctl create addon --cluster k8s-study --region ap-northeast-2 --name eks-pod-identity-agent

# ② EBS CSI 드라이버 애드온 + 권한 연결
eksctl create addon --cluster k8s-study --region ap-northeast-2 \
  --name aws-ebs-csi-driver \
  --pod-identity-associations "namespace=kube-system,serviceAccountName=ebs-csi-controller-sa,permissionPolicyARNs=arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

kubectl get pods -n kube-system | grep ebs-csi
```

예상 출력:
```
ebs-csi-controller-...   6/6   Running     ← EBS API를 부르는 컨트롤러
ebs-csi-node-...         3/3   Running     ← 노드마다: mount/format 담당 (DaemonSet!)
ebs-csi-node-...         3/3   Running
```

✅ 모듈 04의 지식으로 구조가 읽힙니다: controller는 Deployment, node는 DaemonSet.

## Step 2. StorageClass + PVC 생성 — 그리고 "안 만들어지는" 관찰

```bash
kubectl apply -f manifests/storage.yaml
kubectl get pvc data
```

예상 출력:
```
NAME   STATUS    VOLUME   CAPACITY   STORAGECLASS
data   Pending            (없음)      gp3          ← Pending이 정상!
```

✅ **검증 포인트**: `WaitForFirstConsumer` 때문에 **쓰는 Pod가 나타날 때까지** 볼륨을 안 만듭니다. describe로 확인:

```bash
kubectl describe pvc data | tail -3
# → waiting for first consumer to be created before binding
```

## Step 3. Pod가 뜨면 비로소 EBS가 생깁니다

manifests/storage.yaml의 keeper Deployment는 이미 applied 상태입니다:

```bash
kubectl get pods -l app=keeper -w     # ContainerCreating → Running (~1분, EBS 생성+attach 시간)
kubectl get pvc data
```

예상 출력:
```
NAME   STATUS   VOLUME                                     CAPACITY   STORAGECLASS
data   Bound    pvc-3f7a...                                1Gi        gp3
```

```bash
# AWS 쪽 실물 확인
aws ec2 describe-volumes --region ap-northeast-2 \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=data" \
  --query 'Volumes[].{ID:VolumeId,AZ:AvailabilityZone,State:State,Type:VolumeType,Enc:Encrypted}' --output table
```

예상 출력: gp3, encrypted=True, in-use — **PVC 신청서가 진짜 EBS가 됐습니다.** AZ가 keeper Pod의 노드 AZ와 같은지도 비교해보세요.

## Step 4. 데이터 생존 검증 — 이 모듈의 본론

```bash
POD=$(kubectl get pod -l app=keeper -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- sh -c 'echo "survive me" > /data/precious.txt'

# Pod 살해
kubectl delete pod $POD
kubectl wait --for=condition=Ready pod -l app=keeper --timeout=120s

# 새 Pod에서 확인
POD=$(kubectl get pod -l app=keeper -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /data/precious.txt
```

예상 출력:
```
survive me        ← Pod는 죽었지만 데이터는 EBS에 살아있습니다!
```

✅ emptyDir(lab-01)과의 차이가 이 한 줄입니다. 모듈 01 "컨테이너 데이터는 사라진다" 문제의 완결.

## Step 5. RWO의 함정 재현 — replicas를 늘리면

```bash
kubectl scale deployment keeper --replicas=2
sleep 30; kubectl get pods -l app=keeper
```

예상 출력 (두 번째 Pod가 다른 노드에 배정된 경우):
```
keeper-...-aaa   1/1   Running
keeper-...-bbb   0/1   ContainerCreating     ← attach 못 해서 멈춤
```

```bash
kubectl describe pod -l app=keeper | grep -A 3 "Warning"
# → Multi-Attach error for volume ... Volume is already used by pod(s) ...
```

✅ **RWO = 한 노드만.** "디스크 하나를 여러 Pod가 나눠 쓰는" 그림은 EBS로는 안 됩니다(EFS/RWX 필요 — eks 파트). 복원:

```bash
kubectl scale deployment keeper --replicas=1
```

## Step 6. 온라인 볼륨 확장

```bash
kubectl patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
sleep 60
kubectl get pvc data    # CAPACITY 2Gi
POD=$(kubectl get pod -l app=keeper -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- df -h /data | tail -1
```

예상: 파일시스템까지 2.0G로 확장 (Pod 재시작 없이!). 단 **축소는 불가** — 처음부터 과대 신청하지 않는 이유.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| PVC가 Pod 생성 후에도 Pending | CSI 드라이버 미설치/IAM 권한 누락 — `kubectl logs -n kube-system -l app=ebs-csi-controller -c csi-provisioner` |
| Multi-Attach error | RWO 특성 (Step 5) — replicas=1 또는 EFS |
| 확장이 안 먹음 | StorageClass에 `allowVolumeExpansion: true` 있는지 확인 |

## 정리

```bash
bash cleanup.sh    # PVC 삭제 → reclaimPolicy=Delete라 EBS도 자동 삭제됨을 확인
```
