# Lab 01 — EBS CSI Driver IRSA 검증

## 학습 확인 포인트

- [ ] EBS CSI Controller Pod 의 SA 에 IAM Role 어노테이션이 있음을 확인
- [ ] IAM Role Trust Policy 의 `sub` 조건을 직접 봤다
- [ ] Pod 안에서 STS 토큰을 직접 확인

> **🌱 IRSA 의 핵심 메커니즘 한 그림**
> ```
>   Pod (SA: ebs-csi-controller-sa)
>     │ "내 SA 어노테이션엔 IAM Role ARN이 있어"
>     │
>     ↓ AWS SDK가 자동으로
>   STS AssumeRoleWithWebIdentity API 호출
>     │ (SA 토큰을 web identity로 제시)
>     ↓
>   STS가 OIDC issuer 검증 + sub 조건 검증
>     │ "이 토큰의 sub가 Trust Policy의 sub와 일치 → OK"
>     ↓
>   임시 자격증명 발급 (1시간 유효)
>     │
>     ↓
>   Pod이 그 자격증명으로 EBS CreateVolume 등 호출
> ```
>
> **CSI (Container Storage Interface)**: K8s-스토리지 표준 인터페이스. EBS CSI = AWS EBS용 구현체.
> "PVC가 들어오면 CSI가 EBS API 호출 → EBS 생성 → 노드에 attach → 컨테이너에 mount"

## 1. EBS CSI 의 ServiceAccount 확인

```bash
kubectl get sa -n kube-system ebs-csi-controller-sa -o yaml | yq '.metadata.annotations'
```

기대:
```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/AmazonEKS_EBS_CSI_DriverRole
```

→ ClusterConfig 의 `wellKnownPolicies.ebsCSIController: true` 가 자동 셋업.

> **🧠 `eks.amazonaws.com/role-arn` 어노테이션이 마법의 트리거**
> EKS의 mutating webhook이 SA가 부착된 Pod 생성 시 이 어노테이션을 읽고:
> 1. 환경변수 `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` 자동 주입
> 2. SA 토큰을 Pod에 마운트 (`/var/run/secrets/eks.amazonaws.com/serviceaccount/token`)
> → AWS SDK가 자동으로 발견 → STS 호출.
>
> **즉**: 사용자는 어노테이션만 달면 끝. 나머진 EKS가 자동.

## 2. IAM Role 의 Trust Policy 살펴보기

```bash
ROLE_ARN=$(kubectl get sa -n kube-system ebs-csi-controller-sa \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
ROLE_NAME=$(echo $ROLE_ARN | awk -F/ '{print $NF}')
echo "Role: $ROLE_NAME"

aws iam get-role --role-name $ROLE_NAME --query 'Role.AssumeRolePolicyDocument' --output json
```

기대:
```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks..."},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.ap-northeast-2.amazonaws.com/id/XXX:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      }
    }
  }]
}
```

> **🧠 Trust Policy 한 줄씩 읽기**
> - `Principal.Federated`: 이 Role을 빌릴 자격이 있는 외부 신원 제공자 = EKS의 OIDC provider
> - `Action: sts:AssumeRoleWithWebIdentity`: "토큰 가지고 오면 Role 빌려준다" 액션
> - `Condition.sub`: "토큰의 sub claim이 정확히 'system:serviceaccount:<ns>:<sa>' 와 일치해야"
>   → 이게 핵심! 다른 SA가 OIDC 토큰 갖고 있어도 sub 다르면 거부됨
>
> **`sub` (Subject) 형식**: `system:serviceaccount:<namespace>:<sa-name>`
> = K8s SA의 표준 식별자.

## 3. Pod 안에서 토큰 확인

```bash
POD=$(kubectl get pods -n kube-system -l app=ebs-csi-controller -o name | head -1)
kubectl exec -n kube-system $POD -c ebs-plugin -- env | grep AWS
```

> **`-c ebs-plugin`**: Pod에 컨테이너가 여러 개일 때 어느 컨테이너에서 실행할지 지정.
> Pod 다중 컨테이너 (sidecar 등) 일 때 -c 안 붙이면 첫 컨테이너에서 실행.

기대:
```
AWS_DEFAULT_REGION=ap-northeast-2
AWS_REGION=ap-northeast-2
AWS_ROLE_ARN=arn:aws:iam::xxx:role/AmazonEKS_EBS_CSI_DriverRole
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

> **이 4개 환경변수가 IRSA의 모든 것**:
> - `AWS_REGION`: SDK 기본 리전
> - `AWS_ROLE_ARN`: 빌릴 Role
> - `AWS_WEB_IDENTITY_TOKEN_FILE`: 토큰 파일 경로 (SDK가 읽음)
>
> AWS SDK는 이 환경변수만 있으면 자동으로 STS 호출하고 자격증명 캐싱.

```bash
kubectl exec -n kube-system $POD -c ebs-plugin -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | head -c 100
echo
```

JWT 형식. 디코딩하려면:
```bash
kubectl exec -n kube-system $POD -c ebs-plugin -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token \
  | awk -F. '{print $2}' | base64 -d 2>/dev/null
```

> **🧠 JWT (JSON Web Token) 구조**
> ```
>   header.payload.signature
>          ↑
>     세 파트가 점(.)으로 구분, 각각 base64 인코딩됨
> ```
> 두 번째 파트(payload) 가 실제 정보. base64 -d 로 디코드 가능.

기대 (필드들):
```json
{
  "aud": ["sts.amazonaws.com"],
  "exp": ...,
  "iss": "https://oidc.eks.ap-northeast-2.amazonaws.com/id/XXX",
  "kubernetes.io": {
    "namespace": "kube-system",
    "serviceaccount": {"name": "ebs-csi-controller-sa", ...}
  },
  "sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
}
```

→ IAM Role의 Trust 의 `:sub` 조건과 정확히 일치.

> **🧠 JWT 필드 의미**
> - `iss` (Issuer): 토큰 발급자 = EKS OIDC URL
> - `sub` (Subject): 토큰 주인 = 이 SA
> - `aud` (Audience): 토큰을 받을 대상 = STS
> - `exp` (Expiry): 만료 시각 (UNIX timestamp)
>
> AWS는 받은 토큰의 `iss` 가 등록된 OIDC provider인지, `sub` 가 Role Trust의 조건과 일치하는지 검증.

## 4. 실제 EBS API 호출 검증

```bash
# 임의로 PVC 만들어보기
cat > /tmp/test-pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-irsa-pvc
spec:
  storageClassName: gp2
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-irsa
spec:
  containers:
    - name: app
      image: alpine:3.19
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test-irsa-pvc
EOF

kubectl apply -f /tmp/test-pvc.yaml
kubectl get pvc test-irsa-pvc --watch    # Bound 까지 기다림 (몇 초)
```

> **PVC 상태 변화**:
> - `Pending`: PV 매칭 대기 또는 동적 프로비저닝 중
> - `Bound`: PV에 바인딩됨 (사용 가능)
>
> 동적 프로비저닝 흐름:
> 1. PVC 생성 (Pending)
> 2. 스토리지 클래스의 `volumeBindingMode: WaitForFirstConsumer` → Pod 스케줄까지 대기
> 3. Pod이 노드 결정되면 → CSI Controller가 그 AZ에 EBS 생성
> 4. CSI가 PV 객체 만들고 PVC와 바인딩 → `Bound`

EBS CSI Controller 의 로그에서 IRSA 로 EBS API 호출하는 것 확인:
```bash
kubectl logs -n kube-system -l app=ebs-csi-controller -c ebs-plugin --tail=20 \
  | grep -i 'createvolume\|volumeID'
```

## 5. 정리

```bash
kubectl delete -f /tmp/test-pvc.yaml
```

## 학습 확인 질문

1. EBS CSI 의 SA 어노테이션을 다른 IAM Role 의 ARN 으로 바꾸면 어떻게 될까?
2. JWT 토큰의 `:sub` 가 다른 SA 였다면 STS는 어떤 응답을 주는가?
3. Pod이 다중 컨테이너일 때 IRSA 토큰은 어느 컨테이너에 마운트되나?

> **힌트**:
> 1. 새 Role을 빌리려 시도하지만 그 Role의 Trust Policy의 sub 가 이 SA와 일치 안 하면 STS가 거부 → AccessDenied.
> 2. `AccessDenied` (sub 불일치). 토큰 자체는 유효하지만 Trust Policy 조건 불충족.
> 3. **모든 컨테이너에 마운트됨** (Pod 단위 볼륨이라). 컨테이너별로 다른 IAM 권한 분리 X — 필요하면 Pod을 분리.

다음: [lab-02-app-irsa-s3.md](./lab-02-app-irsa-s3.md)
