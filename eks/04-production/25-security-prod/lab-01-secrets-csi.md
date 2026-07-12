# Lab 01 — 시크릿을 클러스터 밖으로: Secrets Manager CSI

k8s Secret의 약점을 **직접 확인**한 뒤, 원본을 AWS로 옮기고 Pod에 파일로 마운트합니다. 09의 Pod Identity가 여기서 다시 열쇠 역할을 합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. 약점 확인 — "암호화된 게 아니다"

```bash
kubectl create ns seclab
kubectl create secret generic legacy -n seclab --from-literal=password=hunter2

# RBAC만 있으면 평문입니다
kubectl get secret legacy -n seclab -o jsonpath='{.data.password}' | base64 -d; echo
```

출력: `hunter2` — base64는 인코딩이지 암호화가 아닙니다(theory §2). etcd 저장 암호화(KMS)를 켜도 **API로 읽을 권한이 있으면 평문**이라는 사실은 변하지 않습니다. 그래서 사다리의 3단, 외부화로 갑니다.

## Step 2. 진짜 금고 — Secrets Manager에 원본을 둡니다

```bash
aws secretsmanager create-secret --region $AWS_REGION \
  --name eks-lab/db --secret-string '{"username":"app","password":"S3cure-2026!"}'
```

## Step 3. 열쇠 배선 — 그 Pod의 SA에만 (09의 최소권한)

```bash
SECRET_ARN=$(aws secretsmanager describe-secret --secret-id eks-lab/db --region $AWS_REGION --query ARN --output text)

cat > sm-policy.json <<EOF
{ "Version": "2012-10-17", "Statement": [{
  "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"],
  "Resource": "$SECRET_ARN" }]}
EOF
aws iam create-policy --policy-name SecretsCsiLab --policy-document file://sm-policy.json 2>/dev/null || true

cat > sm-trust.json <<'EOF'
{ "Version": "2012-10-17", "Statement": [{ "Effect": "Allow",
  "Principal": { "Service": "pods.eks.amazonaws.com" },
  "Action": ["sts:AssumeRole","sts:TagSession"] }]}
EOF
aws iam create-role --role-name SecretsCsiLab --assume-role-policy-document file://sm-trust.json 2>/dev/null || true
aws iam attach-role-policy --role-name SecretsCsiLab \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/SecretsCsiLab

kubectl create serviceaccount app-sa -n seclab
eksctl create podidentityassociation --cluster $CLUSTER --region $AWS_REGION \
  --namespace seclab --service-account-name app-sa \
  --role-arn arn:aws:iam::$ACCOUNT_ID:role/SecretsCsiLab
```

✅ 자원 ARN 하나로 좁힌 정책 — "이 Pod는 이 시크릿 하나만" (넓은 `secretsmanager:*`는 침해 시 전 시크릿 유출).

## Step 4. CSI 드라이버 + AWS 프로바이더

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system --set syncSecret.enabled=false --set enableSecretRotation=true --set rotationPollInterval=60s

kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
kubectl get pods -n kube-system -l 'app in (secrets-store-csi-driver, csi-secrets-store-provider-aws)'
```

## Step 5. SecretProviderClass — "무엇을 어떻게 마운트"

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata: { name: db-secret, namespace: seclab }
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "eks-lab/db"
        objectType: "secretsmanager"
        jmesPath:                        # JSON 필드를 각각 파일로
          - path: username
            objectAlias: db-username
          - path: password
            objectAlias: db-password
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: app, namespace: seclab }
spec:
  serviceAccountName: app-sa
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sleep, "3600"]
    volumeMounts:
    - { name: secrets, mountPath: /mnt/secrets, readOnly: true }
  volumes:
  - name: secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes: { secretProviderClass: db-secret }
EOF
kubectl wait --for=condition=Ready pod/app -n seclab --timeout=120s
```

## Step 6. 결정적 대조 — 원본은 어디에 있나

```bash
# Pod 안에서는 파일로 보입니다
kubectl exec -n seclab app -- cat /mnt/secrets/db-password; echo
kubectl exec -n seclab app -- df -h /mnt/secrets | tail -1      # tmpfs — 디스크에 안 남습니다

# 그런데 클러스터에는 Secret 객체가 없습니다
kubectl get secrets -n seclab | grep -c db || echo "k8s Secret 없음 — 원본은 AWS에"
```

✅ **etcd에 원본이 존재하지 않습니다.** 클러스터 백업(36)이 유출돼도, etcd가 털려도 이 자격증명은 없습니다. 접근 기록은 CloudTrail에 남고(누가 언제 GetSecretValue), 권한은 SA 단위로 좁습니다.

## Step 7. 회전 — 재배포 없이 새 자격증명

```bash
aws secretsmanager put-secret-value --region $AWS_REGION --secret-id eks-lab/db \
  --secret-string '{"username":"app","password":"R0tated-2026!"}'
sleep 90    # rotationPollInterval(60s) + 여유
kubectl exec -n seclab app -- cat /mnt/secrets/db-password; echo
```

예상: `R0tated-2026!` — Pod 재시작 없이 마운트 파일이 갱신됐습니다. ⚠️ 단 **앱이 파일을 다시 읽어야** 의미가 있습니다: 시작 시 한 번만 읽는 앱이라면 회전은 롤링 재시작을 요구합니다(설계 시 확인할 것 — theory §2).

## 정리

seclab은 lab-02에서 계속 사용.
