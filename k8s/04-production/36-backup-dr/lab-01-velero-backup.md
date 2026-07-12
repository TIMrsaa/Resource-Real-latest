# Lab 01 — 지우고 되살리기: Velero 첫 사이클

백업 도구의 신뢰는 "만들었다"가 아니라 "지웠는데 돌아왔다"에서 생깁니다. 이 랩은 그 전체 사이클 — 설치 → 백업 → **삭제** → 복구 → 시간 측정 — 을 한 번에 돕니다.

```bash
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export BUCKET=velero-backup-$ACCOUNT_ID
```

## Step 1. 백업의 집 — S3 버킷과 IAM

```bash
aws s3 mb s3://$BUCKET --region $AWS_REGION

# Velero가 필요한 두 권한: S3(백업 보관) + EBS 스냅샷(볼륨 백업 — lab-02)
cat > velero-policy.json <<'EOF'
{ "Version": "2012-10-17", "Statement": [
  { "Effect": "Allow", "Action": ["ec2:CreateSnapshot","ec2:DeleteSnapshot","ec2:DescribeSnapshots","ec2:DescribeVolumes","ec2:CreateTags"], "Resource": "*" },
  { "Effect": "Allow", "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"], "Resource": ["arn:aws:s3:::*velero*","arn:aws:s3:::*velero*/*"] }
]}
EOF
aws iam create-policy --policy-name VeleroLab --policy-document file://velero-policy.json 2>/dev/null || true
```

## Step 2. 설치 — Pod Identity로 권한을 꽂습니다

08에서 배운 그 배선: SA에 IAM을 연결하면 Velero Pod가 자격증명 없이 AWS를 호출합니다.

```bash
eksctl create podidentityassociation --cluster k8s-study --region $AWS_REGION \
  --namespace velero --service-account-name velero \
  --permission-policy-arns arn:aws:iam::$ACCOUNT_ID:policy/VeleroLab 2>/dev/null || true

# velero CLI 설치 (https://github.com/vmware-tanzu/velero/releases) 후:
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket $BUCKET \
  --backup-location-config region=$AWS_REGION \
  --snapshot-location-config region=$AWS_REGION \
  --use-volume-snapshots=true \
  --no-secret \
  --service-account-name velero

kubectl rollout status deploy/velero -n velero --timeout=120s
velero backup-location get
```

예상: BSL `default`의 PHASE가 **Available** — "백업의 집에 열쇠가 맞다"는 뜻. Unavailable이면 IAM/버킷부터 (백업 이전에 여기가 1차 관문).

## Step 3. 지킬 대상 만들기 — 리소스 여러 종류로

복구 검증을 위해 일부러 다양한 종류(Deployment/ConfigMap/Secret/어노테이션)를 심습니다:

```bash
kubectl create ns shop
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: shop
  labels: { app: web }
spec:
  replicas: 1
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: web
          image: public.ecr.aws/nginx/nginx:1.27
EOF
kubectl create configmap app-settings -n shop --from-literal=theme=dark --from-literal=lang=ko
kubectl create secret generic api-key -n shop --from-literal=key=super-secret
kubectl annotate ns shop owner=team-shop        # 메타데이터까지 돌아오는지 볼 표식
kubectl get all,cm,secret -n shop
```

## Step 4. 백업

```bash
velero backup create shop-backup --include-namespaces shop --wait
velero backup describe shop-backup | grep -E "Phase|Total items|Items backed up"
aws s3 ls s3://$BUCKET/backups/shop-backup/     # 클러스터 밖의 물증
```

예상: `Phase: Completed`, S3에 tarball/메타 파일들. ✅ 이 시점부터 shop ns는 **클러스터가 통째로 사라져도** 존재합니다.

## Step 5. 재해 — 진짜로 지웁니다

```bash
kubectl delete namespace shop
kubectl get ns shop                              # NotFound
kubectl get all -n shop 2>&1 | head -1
```

😱 Deployment, ConfigMap, Secret 전멸 — 09의 pitfall("ns 삭제는 안의 전부를 지운다")을 이번엔 의도적으로 밟았습니다. etcd 스냅샷이 답이라면 "클러스터 전체 되감기"라는 대수술이 필요한 장면입니다.

## Step 6. 부활

```bash
velero restore create shop-restore --from-backup shop-backup --wait
velero restore describe shop-restore | grep Phase
kubectl get all,cm,secret -n shop
```

검증 — 형태만이 아니라 **내용까지**:

```bash
kubectl get cm app-settings -n shop -o jsonpath='{.data.theme}'; echo          # dark
kubectl get secret api-key -n shop -o jsonpath='{.data.key}' | base64 -d; echo # super-secret
kubectl get ns shop -o jsonpath='{.metadata.annotations.owner}'; echo          # team-shop
```

✅ **지운 ns 하나만, 어노테이션까지 정확히 돌아왔습니다** — 다른 ns는 아무 영향 없이. 이것이 "선택 복구"이고, etcd 되감기와의 결정적 차입니다.

## Step 7. 숫자 하나 남기기 — RTO 실측

```bash
velero restore describe shop-restore | grep -E "Started|Completed"
```

Started~Completed가 "shop ns 하나의 RTO 실측값". 이 숫자를 적어두는 습관이 lab-02의 DR 워크시트에서 계획값의 근거가 됩니다 — DR 설계에서 근거 없는 RTO는 소원일 뿐입니다.

## 정리

shop ns와 Velero는 lab-02의 재료 — 그대로 둡니다.
