# Lab 01 — 사전 준비

## 학습 확인 포인트

- [ ] ECR 이미지가 5종 모두 푸시되어 있다
- [ ] order namespace 생성
- [ ] AWS LB Controller 가 동작 중

> **🌱 핵심 개념 미리보기**
> - **ECR** (Elastic Container Registry): AWS의 프라이빗 이미지 레지스트리. Docker Hub의 AWS 버전, IAM으로 권한 제어
> - **마이크로서비스 5종**: `order` / `user` / `payment` / `notification` / `frontend`. NS `order` 한 곳에 모두 배포
> - **노드 IAM Role**: EC2 워커 노드에 붙는 역할. 여기에 ECR 읽기 권한이 있어야 Pod이 이미지 pull 가능
> - **AWS LB Controller**: K8s `Ingress` 리소스를 보고 ALB를 자동 생성/관리하는 컨트롤러
> - **자리표시자 치환**: 매니페스트 안의 `ACCOUNT_ID` 같은 토큰을 `sed`로 실제 값으로 바꾸는 패턴 (Helm 없이 쓰는 가장 단순한 방법)

## 1. ECR 이미지 확인

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

for svc in order-service payment-service user-service notification-service frontend; do
  echo -n "→ $svc: "
  aws ecr describe-images --repository-name eks-study/$svc \
    --query 'imageDetails[?contains(imageTags, `latest`)]|[0].imagePushedAt' \
    --output text 2>/dev/null || echo "NOT FOUND"
done
```

> **🧠 `latest` 태그를 운영에선 왜 피하나?**
> 학습/데모에선 편하지만 운영에선 금기. 같은 태그를 덮어쓰면 어떤 빌드가 떠있는지 추적 불가, 롤백도 어려움.
> 운영 패턴: Git SHA(`sha-abc1234`)나 SemVer(`v1.2.3`) 사용. ECR의 `imageTagMutability=IMMUTABLE` 로 덮어쓰기 자체를 금지하는 것도 방법.

`NOT FOUND` 면 푸시:
```bash
cd ../../
bash 00-prerequisites/scripts/ecr-push-all.sh
cd PART-2-EKS-Practice/09-msa-deploy/
```

## 2. ACCOUNT_ID 치환된 매니페스트 생성

매니페스트 안의 `ACCOUNT_ID` 자리표시자를 치환:

```bash
# 디렉토리 구조를 유지해서 같은 파일명(deployment.yaml 등)이 덮어써지지 않게 함
rm -rf /tmp/msa
for f in manifests/order/*.yaml manifests/user/*.yaml manifests/payment/*.yaml manifests/notification/*.yaml manifests/frontend/*.yaml manifests/base/*.yaml; do
  out="/tmp/msa/${f#manifests/}"
  mkdir -p "$(dirname "$out")"
  sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" "$f" > "$out"
done

# 이후 단계에서는 재귀로 적용
ls -R /tmp/msa/
```

> **🧠 왜 디렉토리 구조를 유지하나?**
> 5개 서비스 모두 같은 파일명(`deployment.yaml`, `service.yaml`)을 쓰기 때문. 평탄하게(`/tmp/msa/deployment.yaml`) 풀면 마지막 서비스 것만 남고 4개가 사라짐.
> `${f#manifests/}` 는 bash 패턴 제거: 접두 `manifests/`만 떼고 나머지 경로(`order/deployment.yaml`)를 보존 → 충돌 0.
>
> **`mkdir -p`** 는 이미 있어도 에러 안 냄. 안전하게 디렉토리 생성하는 표준 패턴.

> **🧠 sed 대신 쓸 만한 도구들**
> - **envsubst**: `envsubst < f.yaml > out.yaml` — `${VAR}` 형태만 치환. 더 명확
> - **Kustomize**: `replacements` / `vars` 로 선언적 치환. K8s 표준 도구 (kubectl 내장)
> - **Helm**: 본격적 템플릿. `{{ .Values.accountId }}` — 의존성/조건/루프까지 가능
>
> 학습 단계에선 sed가 가장 단순. 실 프로덕션은 Helm/Kustomize 권장.

## 3. Namespace 생성

```bash
kubectl apply -f /tmp/msa/base/namespace.yaml
kubectl get ns order
```

## 4. (옵션) ECR Pull 권한 점검

기본적으로 노드 IAM Role에 `AmazonEC2ContainerRegistryReadOnly` 정책이 있어야 ECR pull 가능.

```bash
NODE_ROLE=$(aws eks describe-nodegroup --cluster-name eks-study --nodegroup-name workers \
  --query 'nodegroup.nodeRole' --output text 2>/dev/null | awk -F/ '{print $NF}')
aws iam list-attached-role-policies --role-name $NODE_ROLE \
  --query 'AttachedPolicies[].PolicyName' --output text
```

기대: `AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly`.

`AmazonEC2ContainerRegistryReadOnly` 누락이면 추가:
```bash
aws iam attach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

> **🧠 ECR pull은 어떻게 인증되나?**
> kubelet이 ECR을 만나면 노드의 IAM Role 자격증명으로 `ecr:GetAuthorizationToken` 호출 → 12시간짜리 임시 도커 자격증명을 받아 pull.
> 그래서 imagePullSecrets 같은 거 만들 필요 없음. 이게 동작 안 하면 Pod 이벤트에 `ImagePullBackOff` + `no basic auth credentials`.
>
> Karpenter나 Pod Identity 환경에서도 결국 노드 Role(또는 Pod의 IRSA)에 ECR 권한이 있어야 함.

## 5. AWS LB Controller 동작 점검

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get ingressclass alb
```

기대: 컨트롤러 Pod 2개 Running, IngressClass `alb` 존재.

> **🧠 Pod 2개 / IngressClass 의 의미**
> - **Pod 2개**: HA를 위해 leader-election 으로 Active/Standby 운영. 한쪽 죽어도 다른쪽이 ALB 동기화 이어감
> - **IngressClass `alb`**: Ingress 의 `spec.ingressClassName: alb` 와 매칭되는 워커 식별자. 한 클러스터에 여러 컨트롤러 공존 가능 (예: `nginx`, `alb`)
>
> Ingress 가 만들어졌는데 ALB 가 안 뜨면 컨트롤러 로그(`kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller`) 부터 확인.

## 학습 확인 질문

1. `AmazonEC2ContainerRegistryReadOnly` 가 노드 IAM Role 에 없으면 어떤 에러가 발생하는가?
2. ServiceMonitor 가 `monitoring` NS 에 있는데 `order` NS 의 Service 를 scrape 할 수 있는 이유는?
3. 매니페스트의 `ACCOUNT_ID` 자리표시자를 치환하는 방법으로 sed 외에 어떤 게 있을까?

다음: [lab-02-deploy-services.md](./lab-02-deploy-services.md)
