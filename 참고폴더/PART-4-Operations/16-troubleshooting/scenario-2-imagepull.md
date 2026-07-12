# 시나리오 2 — ImagePullBackOff

> **🌱 ImagePullBackOff 가 뭔가?**
> kubelet이 컨테이너 이미지를 registry(Docker Hub/ECR 등) 에서 pull 하다 실패 → 재시도.
> 또 실패 → 재시도 간격 늘림 → BackOff.
>
> 두 단계:
> - **`ErrImagePull`**: 첫 시도 실패 (즉시 표시)
> - **`ImagePullBackOff`**: 여러 번 실패 후 BackOff 대기

## 1. 재현

오타가 있는 이미지로 Pod 만들기:
```bash
kubectl run badimg --image=public.ecr.aws/eks-distro/no-such-image:v999
sleep 30
```

## 2. 증상

```bash
kubectl get pod badimg
```

```
NAME     READY   STATUS             RESTARTS   AGE
badimg   0/1     ErrImagePull       0          15s
# 또는 ImagePullBackOff
```

## 3. 진단

```bash
kubectl describe pod badimg | tail -20
```

기대 (Events):
```
Failed to pull image "...no-such-image:v999": ... manifest unknown
```

> **🧠 핵심: Events 의 에러 메시지가 정확한 원인 알려줌**
> - `manifest unknown` / `not found` → 이미지/태그 오타
> - `unauthorized` → 인증 실패
> - `pull access denied` → 권한 거부 (사설 레포)
> - `dial tcp: i/o timeout` → 네트워크 (NAT, DNS, 방화벽)

## 4. 원인 분류

| 메시지 | 원인 |
|--------|------|
| `manifest unknown` / `not found` | 이미지 이름 / 태그 오타 |
| `unauthorized` / `denied` | 사설 레지스트리 인증 누락 |
| `no basic auth credentials` | ECR — 노드 IAM Role 의 ECR 권한 누락 |
| `dial tcp ... timeout` | 네트워크 (NAT GW 없음, VPC endpoint 미설정) |

> **🧠 ECR 인증의 특이점**
> ECR은 username/password 가 아니라 **IAM 인증** 사용.
> EKS 노드는 IAM Role에 `AmazonEC2ContainerRegistryReadOnly` 정책 있으면 자동으로 ECR pull 가능.
> = SA(IRSA) 가 아닌 **노드 IAM**. (Pod이 직접 ECR 호출하는 게 아니라 kubelet이 호출)

## 5. 해결 — 각 원인별

### 5.1 오타 / 잘못된 태그
```bash
# 사용 가능한 태그 확인
aws ecr describe-images --repository-name eks-study/order-service \
  --query 'imageDetails[].imageTags' | jq
```

> **태그 vs 다이제스트**: `nginx:1.27` 은 가변 (재푸시되면 바뀔 수 있음).
> `nginx@sha256:abc123...` 는 불변 (이미지 콘텐츠 해시).
> 운영에선 다이제스트로 고정 권장.

### 5.2 ECR 권한
```bash
NODE_ROLE=$(aws eks describe-nodegroup --cluster-name eks-study --nodegroup-name workers \
  --query 'nodegroup.nodeRole' --output text | awk -F/ '{print $NF}')
aws iam attach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

> **노드 IAM 변경 후 즉시 반영?** 네, 다음 pull부터. Pod 재시작은 K8s 가 BackOff 만료 후 자동 시도.
> 빨리 보려면 `kubectl delete pod` 로 강제 재생성.

### 5.3 사설 레지스트리 (Docker Hub 인증 등)
```bash
kubectl create secret docker-registry myregistry \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=USERNAME \
  --docker-password=PASSWORD

# Pod spec 에 imagePullSecrets 추가
```

> **🧠 `imagePullSecrets` 사용**
> ```yaml
> spec:
>   imagePullSecrets:
>     - name: myregistry
>   containers:
>     - image: myorg/private-app:1.0
> ```
> 또는 ServiceAccount에 부착 → 그 SA 쓰는 모든 Pod에 자동 적용.
>
> **Docker Hub Rate Limit**: 익명 200 pull/6h. 인증 5000/6h. 학습/CI 환경에선 자주 도달.

## 6. 정리

```bash
kubectl delete pod badimg
```

## 학습 확인

- ECR 노드 IAM Role 의 정책 이름은?
- Pod 가 `ErrImagePull` 상태 후 `ImagePullBackOff` 로 가는 경계는?
- 같은 이미지를 같은 노드에 여러 번 pull 하면 캐시 동작은?

> **힌트**:
> - `AmazonEC2ContainerRegistryReadOnly` (read 전용) 또는 `AmazonEC2ContainerRegistryPowerUser` (push도).
> - 첫 시도 실패 → ErrImagePull. 재시도 누적되며 BackOff 간격이 적용되면 → ImagePullBackOff. 명확한 횟수 경계는 없음 (kubelet 내부 정책).
> - 노드의 containerd가 캐시 (`imagePullPolicy` 따름). `IfNotPresent` (기본) = 노드에 있으면 안 받음. `Always` = 항상 받음 (latest 태그 권장). `Never` = 절대 안 받음.
