# Lab 01 — EBS 운영 동작 3종: 스냅샷, 복원, 온라인 확장

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl create ns storage-lab
```

## Step 0. EBS CSI 드라이버 확인 (없으면 애드온으로)

```bash
kubectl get pods -n kube-system | grep ebs-csi || {
  eksctl create podidentityassociation --cluster $CLUSTER --region $AWS_REGION \
    --namespace kube-system --service-account-name ebs-csi-controller-sa \
    --permission-policy-arns arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true
  aws eks create-addon --cluster-name $CLUSTER --addon-name aws-ebs-csi-driver --region $AWS_REGION
  sleep 60; kubectl get pods -n kube-system | grep ebs-csi
}
# 스냅샷 CRD/컨트롤러 (external-snapshotter)
kubectl get crd volumesnapshots.snapshot.storage.k8s.io 2>/dev/null || {
  SNAP=https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master
  kubectl apply -f $SNAP/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml \
    -f $SNAP/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml \
    -f $SNAP/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml \
    -f $SNAP/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml \
    -f $SNAP/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml
}
```

## Step 1. 확장 가능한 StorageClass + 데이터

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: gp3-x }
provisioner: ebs.csi.aws.com
parameters: { type: gp3, encrypted: "true" }
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data, namespace: storage-lab }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3-x
  resources: { requests: { storage: 4Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: writer, namespace: storage-lab }
spec:
  volumes: [{ name: d, persistentVolumeClaim: { claimName: data } }]
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sh, -c, 'echo "v1 precious" > /data/file && df -h /data && sleep 3600']
    volumeMounts: [{ name: d, mountPath: /data }]
EOF
kubectl wait --for=condition=Ready pod/writer -n storage-lab --timeout=180s
kubectl logs writer -n storage-lab    # 4G 마운트 확인
```

## Step 2. 스냅샷 — 보험 들기

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata: { name: ebs-snap }
driver: ebs.csi.aws.com
deletionPolicy: Delete
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: { name: data-snap, namespace: storage-lab }
spec:
  volumeSnapshotClassName: ebs-snap
  source: { persistentVolumeClaimName: data }
EOF
kubectl get volumesnapshot -n storage-lab -w    # READYTOUSE: true 대기 (~1분)
```

```bash
# AWS 실물 대조
aws ec2 describe-snapshots --owner-ids self --region $AWS_REGION \
  --query 'Snapshots[?starts_with(Description,`Created by`)].{id:SnapshotId,state:State,size:VolumeSize}' --output table | head -8
```

✅ VolumeSnapshot(K8s 객체) ↔ EBS 스냅샷(실물) — k8s 36에서 Velero가 내부적으로 쓰던 그 체계를 직접 조작했습니다.

## Step 3. 사고와 복원 — 스냅샷에서 새 PVC

```bash
# 사고: 데이터 파괴
kubectl exec writer -n storage-lab -- sh -c 'rm /data/file && ls /data'
# 복원: dataSource로 새 PVC
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data-restored, namespace: storage-lab }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3-x
  dataSource: { name: data-snap, kind: VolumeSnapshot, apiGroup: snapshot.storage.k8s.io }
  resources: { requests: { storage: 4Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: reader, namespace: storage-lab }
spec:
  volumes: [{ name: d, persistentVolumeClaim: { claimName: data-restored } }]
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sh, -c, 'cat /data/file && sleep 600']
    volumeMounts: [{ name: d, mountPath: /data }]
EOF
kubectl wait --for=condition=Ready pod/reader -n storage-lab --timeout=180s
kubectl logs reader -n storage-lab    # → v1 precious  부활!
```

✅ **삭제된 데이터가 스냅샷 시점으로 돌아왔습니다** — 마이그레이션/위험 작업 전 "보험"의 전 과정. staging에 운영 데이터 사본을 만드는 패턴도 이와 동일.

## Step 4. 온라인 확장 — 무중단 디스크 증설

```bash
kubectl exec writer -n storage-lab -- df -h /data | tail -1     # 4G
kubectl patch pvc data -n storage-lab \
  -p '{"spec":{"resources":{"requests":{"storage":"8Gi"}}}}'
# 진행 관찰 (~1-2분: ModifyVolume → FS 확장)
kubectl get pvc data -n storage-lab -w
kubectl exec writer -n storage-lab -- df -h /data | tail -1     # 8G — Pod 재시작 없이!
```

✅ **패치 한 줄 = 무중단 증설.** 새벽 "디스크 90%" 알림의 대응이 이 한 줄입니다 (단: allowVolumeExpansion, 축소 불가, 같은 볼륨 6시간 쿨다운 기억).

## 정리

스냅샷/리소스는 lab-02 후 cleanup에서 일괄 — 진행 중이면 유지.
