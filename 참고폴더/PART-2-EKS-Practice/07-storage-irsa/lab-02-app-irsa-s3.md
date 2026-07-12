# Lab 02 — 앱에 IRSA 적용 (S3 접근)

목표: AWS CLI 가 들어있는 Pod 에 IRSA 로 S3 ReadOnly 권한 부여 → S3 버킷 목록 조회.

## 학습 확인 포인트

- [ ] `eksctl create iamserviceaccount` 가 무엇을 만드는지 직접 확인
- [ ] IRSA 없이 호출 → 실패, IRSA 있으면 성공 → 비교
- [ ] IAM Policy 변경이 즉시 반영됨 (Pod 재시작 불필요)

> **🌱 이 lab의 의미**
> Lab 01은 EBS CSI(AWS 컴포넌트) 의 IRSA를 관찰만 했음.
> 이 lab은 **사용자 Pod에 직접 IRSA 적용**. 실제 앱이 AWS API 부르는 표준 패턴.

## 1. 실습용 S3 버킷 만들기

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="eks-study-irsa-${ACCOUNT_ID}"

aws s3 mb s3://${BUCKET_NAME} --region ap-northeast-2
echo "test content" | aws s3 cp - s3://${BUCKET_NAME}/test.txt
aws s3 ls s3://${BUCKET_NAME}/
```

> **`aws s3 mb`**: "make bucket". 버킷 이름은 전 세계 유일해야 하므로 ACCOUNT_ID 붙임.

## 2. IRSA 없이 시도 — 실패 케이스

```bash
cat > /tmp/no-irsa-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: s3-no-irsa
spec:
  containers:
    - name: aws
      image: amazon/aws-cli:2.15.0
      command: ["sleep", "3600"]
EOF

kubectl apply -f /tmp/no-irsa-pod.yaml
kubectl wait --for=condition=ready pod s3-no-irsa --timeout=60s

kubectl exec s3-no-irsa -- aws s3 ls s3://${BUCKET_NAME}/
```

기대:
```
Unable to locate credentials. You can configure credentials by running "aws configure".
```

(또는 노드 IAM Role 권한이 있으면 성공할 수도 있음 — 그 경우 의도 불명확. 다음 단계로)

> **🧠 왜 실패하는가? 자격증명 발견 순서**
> AWS SDK는 다음 순서로 자격증명 찾음:
> 1. 환경변수 (AWS_ACCESS_KEY_ID 등)
> 2. SSO/공유 config 파일 (`~/.aws/credentials`)
> 3. ECS 컨테이너 자격증명 엔드포인트
> 4. **EKS Pod Identity** (eks-pod-identity-agent 동작 시)
> 5. **IRSA** (AWS_WEB_IDENTITY_TOKEN_FILE + AWS_ROLE_ARN)
> 6. **IMDSv2** (EC2 인스턴스 메타데이터 = 노드 IAM Role)
>
> 이 Pod은 1~5번 다 없음 → 6번에서 노드 IAM 시도 → 노드 IAM에 S3 권한 없으면 실패.
>
> **운영에서 노드 IAM 의존 금지** 이유: 어떤 Pod이든 노드 권한 다 쓸 수 있음 (보안 ↓).

```bash
kubectl delete -f /tmp/no-irsa-pod.yaml
```

## 3. IRSA SA 생성 (eksctl)

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=default \
  --name=s3-reader \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve \
  --region=ap-northeast-2

kubectl get sa s3-reader -o yaml | yq '.metadata.annotations'
```

기대: `eks.amazonaws.com/role-arn` 이 채워져 있음.

> **🧠 이 한 명령이 만드는 것 4가지**
> 1. **CloudFormation Stack** (eksctl이 모든 리소스를 CFN으로 관리)
> 2. **IAM Role** (Trust: 클러스터 OIDC + sub=`system:serviceaccount:default:s3-reader`)
> 3. **IAM Role에 정책 attach** (`AmazonS3ReadOnlyAccess`)
> 4. **K8s ServiceAccount** (`default/s3-reader`, 어노테이션 부착)
>
> 수동으로 하면 4단계 + JSON Trust 정책 작성. eksctl 한 줄로 끝.

## 4. IRSA 로 Pod 실행

```bash
cat > /tmp/irsa-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: s3-with-irsa
spec:
  serviceAccountName: s3-reader        # ← 이 한 줄이 IRSA의 모든 것
  containers:
    - name: aws
      image: amazon/aws-cli:2.15.0
      command: ["sleep", "3600"]
EOF

kubectl apply -f /tmp/irsa-pod.yaml
kubectl wait --for=condition=ready pod s3-with-irsa --timeout=60s

# 환경변수 자동 주입 확인
kubectl exec s3-with-irsa -- env | grep AWS
```

기대: `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` 자동으로 보임.

> **🧠 환경변수가 어디서 왔나?**
> `serviceAccountName: s3-reader` 적은 순간 EKS의 mutating admission webhook이:
> 1. SA의 `eks.amazonaws.com/role-arn` 어노테이션 읽음
> 2. Pod spec에 `env: AWS_ROLE_ARN=...` 자동 추가
> 3. SA 토큰을 마운트하는 projected volume 자동 추가
>
> = Pod YAML에 IRSA 관련 항목 0줄. SA 이름만 적으면 끝.

## 5. 실제 호출

```bash
# 정체 확인 — STS 가 임시 자격증명을 줬는지
kubectl exec s3-with-irsa -- aws sts get-caller-identity

# S3 호출
kubectl exec s3-with-irsa -- aws s3 ls s3://${BUCKET_NAME}/
kubectl exec s3-with-irsa -- aws s3 cp s3://${BUCKET_NAME}/test.txt -
```

기대: 성공.

> **`aws sts get-caller-identity` 의 응답**:
> ```json
> {
>   "UserId": "AROAEXAMPLE:botocore-session-...",
>   "Account": "123456789012",
>   "Arn": "arn:aws:sts::123456789012:assumed-role/<RoleName>/<session-name>"
> }
> ```
> `assumed-role/...` = STS로 임시 자격증명 받은 상태. IRSA 동작 증거.
> 노드 IAM 이었다면 `assumed-role/eksctl-*-NodeInstanceRole/...` 이었을 것.

## 6. 권한 한계 시연 — 쓰기 시도

```bash
echo "from-pod" | kubectl exec -i s3-with-irsa -- aws s3 cp - s3://${BUCKET_NAME}/from-pod.txt
```

기대:
```
upload failed: ... AccessDenied
```

ReadOnly 정책이라 PUT 거부.

> **`-i` 플래그**: stdin 을 컨테이너로 전달. echo 출력을 컨테이너 안 aws cli에 넘김.
>
> **AccessDenied 의 의미**: STS는 잘 동작했지만 (= 자격증명 OK) IAM Policy가 PutObject 권한 없음.
> 흔한 트러블슈팅: AccessDenied 보면 "토큰 문제? Role 문제? Policy 문제?" 로 분리해서 봐야.

## 7. 권한 추가 — Trust 와 Policy 변경 즉시 반영

기존 Role 에 정책 추가:
```bash
ROLE_ARN=$(kubectl get sa s3-reader -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
ROLE_NAME=$(echo $ROLE_ARN | awk -F/ '{print $NF}')

aws iam attach-role-policy --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Pod 재시작 없이 다시 시도
sleep 10   # 자격증명 캐싱 만료 대기 (보통 5분이지만 새 호출은 새 토큰)
kubectl exec s3-with-irsa -- aws s3 cp /etc/hostname s3://${BUCKET_NAME}/from-pod.txt
kubectl exec s3-with-irsa -- aws s3 ls s3://${BUCKET_NAME}/
```

기대: 성공 (PUT 권한 부여됨).

> **🧠 왜 Pod 재시작 없이 반영되는가?**
> IRSA는 매 API 호출마다 STS 토큰을 새로 받지 않음. SDK가 자격증명을 캐싱(기본 ~1시간).
> 하지만 IAM Policy 변경은 **다음 STS AssumeRoleWithWebIdentity 호출 시 즉시 반영** (정책은 평가 시점 기준).
>
> 실험적으론:
> - 캐시된 자격증명 = 옛 권한 (만료까지 유지)
> - 새 SDK 인스턴스 / 새 Pod = 즉시 새 권한
>
> 운영에선 이런 권한 변경이 즉시 모든 Pod에 반영되길 원하면 → Pod 재시작이 가장 확실.

> **주의**: 자격증명은 STS 토큰 캐시 (~1시간). 즉시 변화는 컨테이너의 SDK 가 자격증명을 새로 가져올 때 반영. 새 Pod 면 즉시.

## 8. 정리

```bash
kubectl delete -f /tmp/irsa-pod.yaml
eksctl delete iamserviceaccount --cluster=eks-study --namespace=default --name=s3-reader \
  --region=ap-northeast-2 --wait

# S3 버킷 삭제
aws s3 rm s3://${BUCKET_NAME} --recursive
aws s3 rb s3://${BUCKET_NAME}
```

> **`eksctl delete iamserviceaccount`** 가 정리하는 것:
> - K8s SA 삭제
> - IAM Role 삭제
> - 정책 detach
> - CFN 스택 삭제
>
> 수동 IRSA를 만들었다면 직접 cleanup 필요.

## 학습 확인 질문

1. `aws sts get-caller-identity` 의 응답에서 `Arn` 가 어떤 형태였나? (assumed-role/...)
2. 같은 IAM Role 을 두 개의 SA 에 매핑하고 싶으면 Trust Policy 의 sub 조건은 어떻게 작성?
3. Pod 의 토큰이 만료되면 어떻게 갱신되나?

> **힌트**:
> 1. `arn:aws:sts::ACCOUNT:assumed-role/RoleName/session-name` 형식. assumed-role 이 IRSA 동작 증거.
> 2. `StringEquals` 대신 `StringLike` 또는 sub 값을 배열로:
>    ```json
>    "...:sub": ["system:serviceaccount:ns1:sa1", "system:serviceaccount:ns2:sa2"]
>    ```
>    하지만 이게 IRSA의 약점 → Pod Identity가 해결 (lab-03).
> 3. K8s가 SA 토큰을 주기적으로(~1시간) 자동 갱신. AWS SDK도 토큰 만료 감지하면 STS 재호출하여 자격증명 갱신.

다음: [lab-03-pod-identity.md](./lab-03-pod-identity.md)
