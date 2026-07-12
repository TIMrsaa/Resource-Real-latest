# Lab 02 — CSI 해부: PVC 한 장의 여정을 사이드카별로 추적

교과서 CSI 드라이버(hostpath)를 kind에 설치하고, PVC→PV→마운트의 전 과정을 컴포넌트별 로그로 따라갑니다 — eks에서 EBS CSI를 "쓰기만" 했던 것의 내부입니다.

전제: kind, kubectl. 메모리 4GB+.

## Step 1. 클러스터와 CSI 드라이버 설치

```bash
kind create cluster --name csi -q

# 교과서 드라이버: csi-driver-host-path (노드 디렉터리를 볼륨으로 — 학습용)
BASE=https://raw.githubusercontent.com/kubernetes-csi/csi-driver-host-path/master
kubectl apply -f $BASE/deploy/kubernetes-1.30/hostpath/csi-hostpath-driverinfo.yaml 2>/dev/null || \
  { git clone --depth 1 https://github.com/kubernetes-csi/csi-driver-host-path.git ~/cncf-lab/csi-hostpath
    ~/cncf-lab/csi-hostpath/deploy/kubernetes-latest/deploy.sh; }
kubectl get pods -o wide | head -8
```

예상: csi-hostpath 계열 Pod들 Running. 구성을 확인하면:

```bash
kubectl get pod -l app.kubernetes.io/name=csi-hostpathplugin \
  -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null; echo
```

예상: `hostpath`(벤더 드라이버) 옆에 **external-provisioner, external-attacher, node-driver-registrar, external-snapshotter...** — theory §1의 사이드카 군단이 실물로. ✅ 벤더 코드는 hostpath 하나, 나머지는 **모든 CSI 드라이버가 공유하는 공용 행정팀**입니다.

## Step 2. StorageClass와 PVC — 여정의 시작

```bash
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: csi-hostpath-sc }
provisioner: hostpath.csi.k8s.io      # ★ 어느 드라이버가 담당하는지의 연결 고리
volumeBindingMode: WaitForFirstConsumer  # Pod가 뜰 노드를 알아야 만드는 지연 바인딩
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: csi-hostpath-sc
  resources: { requests: { storage: 1Gi } }
EOF

kubectl get pvc data        # Pending — WaitForFirstConsumer라 소비자를 기다리는 중!
```

예상: **Pending**. 고장이 아닙니다 — 지연 바인딩은 "Pod가 어느 노드에 뜰지" 알아야 그 노드에 맞는 볼륨을 만들 수 있어서입니다(토폴로지 — EBS의 AZ 제약과 같은 문제, eks의 그 함정).

## Step 3. 소비자 등장 — 프로비저닝의 발화

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh","-c","echo hello-csi > /data/proof.txt && sleep 3600"]
      volumeMounts: [{ name: vol, mountPath: /data }]
  volumes:
    - name: vol
      persistentVolumeClaim: { claimName: data }
EOF
kubectl wait --for=condition=ready pod/writer --timeout=120s
kubectl get pvc data && kubectl get pv | head -3
```

예상: PVC Bound, PV 자동 생성. 이제 여정을 로그로 재구성:

```bash
# ① provisioner: PVC를 보고 CreateVolume을 호출한 기록
kubectl logs -l app.kubernetes.io/name=csi-hostpathplugin -c csi-provisioner --tail=50 2>/dev/null \
  | grep -E "provision|CreateVolume|data" | head -4

# ② 벤더 드라이버: 실제 볼륨 생성
kubectl logs -l app.kubernetes.io/name=csi-hostpathplugin -c hostpath --tail=50 2>/dev/null \
  | grep -iE "createvolume|nodepublish" | head -4
```

✅ **PVC(선언) → provisioner(감시·발주) → 드라이버 CreateVolume(시공) → PV(등기) → kubelet NodePublish(입주)** — 여정의 각 발자국이 다른 컴포넌트의 로그에 있습니다. 진단이 층으로 나뉜다는 말의 실체(theory §1).

## Step 4. 데이터의 실증과 스냅샷 표준

```bash
kubectl exec writer -- cat /data/proof.txt         # hello-csi

# CSI 스냅샷 — Velero(k8s 36)가 타는 그 표준
kubectl apply -f - <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata: { name: data-snap }
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source: { persistentVolumeClaimName: data }
EOF
sleep 5
kubectl get volumesnapshot data-snap -o jsonpath='{.status.readyToUse}'; echo
```

예상: `true` — 스냅샷 생성. ✅ VolumeSnapshot CRD는 **드라이버 중립 표준** — EBS든 Ceph든 같은 API로 스냅샷하고, Velero가 이 위에서 백업을 짓습니다(스토리지와 백업이 한 세트인 이유 — guide).

## Step 5. 진단 훈련 — 층 판정 연습

```markdown
# 증상 → 층 → 보는 곳 (오늘 확인한 구조 기반)
| 증상 | 층 | 보는 곳 |
|------|----|---------|
| PVC가 Pending (소비자 있는데) | 프로비저닝 | provisioner 로그, StorageClass의 provisioner 이름 오타, 드라이버 Pod 상태 |
| Pod가 ContainerCreating에 고착 + Multi-Attach 에러 | 어태치 | attacher 로그, RWO 볼륨을 두 노드가 다투는지 (블록≠RWX!) |
| MountVolume.SetUp failed | 노드/마운트 | kubelet 로그, node-driver-registrar, 노드의 드라이버 소켓 |
| 스냅샷 안 됨 | 스냅샷 | snapshotter 로그, VolumeSnapshotClass 존재 여부 |
★ eks의 EBS CSI 장애도 같은 층 구조 — 이 표가 그대로 통합니다
```

## 정리

```bash
bash cleanup.sh
```
