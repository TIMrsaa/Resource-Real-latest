# Lab 02 — EFS: RWX의 실증과 선택표 완성

> ⚠️ EFS 파일시스템은 시간당+GB 과금 — lab 후 cleanup 필수.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. EFS 파일시스템 + mount target (인프라 영역)

```bash
VPC_ID=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)
FS_ID=$(aws efs create-file-system --region $AWS_REGION \
  --performance-mode generalPurpose --throughput-mode elastic \
  --tags Key=Name,Value=eks-lab --query 'FileSystemId' --output text)
echo $FS_ID

# 노드 SG에서 NFS(2049) 허용 + 각 서브넷에 mount target
NODE_SG=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
for SUBNET in $(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.subnetIds[]' --output text); do
  aws efs create-mount-target --file-system-id $FS_ID --subnet-id $SUBNET \
    --security-groups $NODE_SG --region $AWS_REGION 2>/dev/null || true
done
sleep 60   # mount target available 대기
```

## Step 2. EFS CSI 드라이버 (애드온) + StorageClass

```bash
eksctl create podidentityassociation --cluster $CLUSTER --region $AWS_REGION \
  --namespace kube-system --service-account-name efs-csi-controller-sa \
  --permission-policy-arns arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy 2>/dev/null || true
aws eks create-addon --cluster-name $CLUSTER --addon-name aws-efs-csi-driver --region $AWS_REGION 2>/dev/null || true
sleep 45; kubectl get pods -n kube-system | grep efs-csi | head -3

cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: efs-ap }
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: $FS_ID
  directoryPerms: "700"
EOF
```

## Step 3. RWX — 드디어 "여럿이 동시에"

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: shared, namespace: storage-lab }
spec:
  accessModes: [ReadWriteMany]        # ★ k8s 08에서 EBS가 거부하던 그것
  storageClassName: efs-ap
  resources: { requests: { storage: 1Gi } }   # EFS에선 형식상 값
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: sharers, namespace: storage-lab }
spec:
  replicas: 3
  selector: { matchLabels: { app: sharers } }
  template:
    metadata: { labels: { app: sharers } }
    spec:
      volumes: [{ name: s, persistentVolumeClaim: { claimName: shared } }]
      containers:
      - name: c
        image: public.ecr.aws/docker/library/busybox:stable
        command: [sh, -c, 'while true; do echo "$(hostname) $(date +%T)" >> /shared/log; sleep 5; done']
        volumeMounts: [{ name: s, mountPath: /shared }]
EOF
kubectl wait --for=condition=Available deploy/sharers -n storage-lab --timeout=180s
kubectl get pods -n storage-lab -l app=sharers -o wide    # 여러 노드에 분산됐는지 확인
```

```bash
# 세 Pod이 같은 파일에 쓰고 있습니다!
kubectl exec -n storage-lab deploy/sharers -- tail -6 /shared/log
```

예상: 서로 다른 hostname 3개가 섞여 찍힙니다.

✅ **RWX의 실증** — k8s 08에서 EBS Multi-Attach 에러로 배운 "블록은 한 명만"의 반대편. 여러 노드의 Pod이 같은 파일시스템에 동시 기록. AZ도 무관(EFS는 리전 서비스).

## Step 4. access point — PVC마다 격리된 방

```bash
aws efs describe-access-points --file-system-id $FS_ID --region $AWS_REGION \
  --query 'AccessPoints[].{id:AccessPointId,path:RootDirectory.Path}' --output table
```

✅ PVC 하나 = access point 하나(전용 디렉터리+POSIX 신원) — **한 파일시스템을 여러 PVC가 격리 공유**하는 동적 프로비저닝의 실체. 테넌트별 공유 볼륨(k8s 34)에도 같은 패턴.

## Step 5. 성격 차이 실측 — EBS vs EFS 지연

```bash
kubectl exec writer -n storage-lab -- sh -c 'time sh -c "for i in $(seq 1 200); do echo x > /data/t$i; done"' 2>&1 | tail -2
kubectl exec -n storage-lab deploy/sharers -- sh -c 'time sh -c "for i in $(seq 1 200); do echo x > /shared/t$i; done"' 2>&1 | tail -2
```

예상: 작은 파일 200개 생성이 EFS에서 수 배 느립니다 (네트워크 파일시스템 + 메타데이터 왕복).

✅ **"DB를 EFS에 올리지 마라"의 숫자 근거** — 소량 랜덤 IO는 EFS의 약점. 용도별 성격(theory §5)이 벤치마크로 확인됐습니다.

## Step 6. S3 CSI는 결정표로 (설치는 선택)

Mountpoint S3 CSI는 설치보다 **자리**가 중요합니다 — 결정표를 완성하세요:

```markdown
# 스토리지 결정표 (우리 클러스터) — 산출물
| 데이터 | 선택 | 한 줄 근거 |
|--------|------|-----------|
| PostgreSQL 데이터 | EBS gp3 (RWO) | 저지연 블록, Step 5의 숫자 |
| 사용자 업로드 (3 Pod 서빙) | EFS (RWX) | Step 3의 실증 |
| ML 학습 데이터 50TB 읽기 | S3 CSI | 용량 단가 + 순차 읽기 |
| 빌드 캐시 | emptyDir | 영속 불필요 |
| 백업 보관 | S3 (SDK 직접) | 파일시스템 흉내 불필요 |
운영 수칙: PVC엔 보존 정책 명시(k8s 19), 스냅샷은 TTL과 함께, EFS엔 DB 금지
```

## 정리 (★ 과금 차단)

```bash
bash cleanup.sh
```
