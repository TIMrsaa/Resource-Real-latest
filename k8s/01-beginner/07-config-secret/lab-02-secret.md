# Lab 02 — Secret: 환상 깨기와 보호 계층 확인

## Step 1. Secret 생성과 base64 까보기

```bash
kubectl create secret generic db-cred \
  --from-literal=username=admin \
  --from-literal=password='S3cr3t!pass'

kubectl get secret db-cred -o yaml | grep -A 3 "^data:"
```

예상 출력:
```
data:
  password: UzNjcjN0IXBhc3M=
  username: YWRtaW4=
```

```bash
# 1초 해독
kubectl get secret db-cred -o jsonpath='{.data.password}' | base64 -d; echo
```

예상 출력:
```
S3cr3t!pass        ← 이것이 "base64는 보안이 아니다"의 전부
```

✅ **핵심**: `get secret` 권한이 있으면 평문이나 마찬가지입니다. 그래서 보호의 본체는 **RBAC**(모듈 11)입니다.

## Step 2. Pod에 주입 (ConfigMap과 동일 문법)

```bash
kubectl patch deployment config-demo --type=json -p='[
  {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"secret-vol","secret":{"secretName":"db-cred"}}},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"secret-vol","mountPath":"/etc/secret","readOnly":true}}]'
kubectl rollout status deployment config-demo
POD=$(kubectl get pod -l app=config-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -- cat /etc/secret/password; echo
```

예상 출력: `S3cr3t!pass` (컨테이너 안에서는 **디코딩된 평문 파일**)

## Step 3. tmpfs 확인 — 디스크에 안 남습니다

```bash
kubectl exec $POD -- sh -c 'mount | grep /etc/secret'
```

예상 출력:
```
tmpfs on /etc/secret type tmpfs ...      ← 램 파일시스템! 노드 디스크에 안 씀
```

✅ 보호 계층 ①을 직접 확인. 노드가 꺼지면 흔적도 사라집니다.

## Step 4. EKS의 저장 시 암호화(계층 ④) 확인

```bash
aws eks describe-cluster --name k8s-study --region ap-northeast-2 \
  --query 'cluster.encryptionConfig' --output json
```

예상: EKS는 2024년 이후 생성 클러스터에서 **KMS 봉투 암호화가 기본** — etcd를 통째로 훔쳐도 KMS 키 없이는 못 읽습니다. (응답이 null이면 구버전 클러스터 — 콘솔에서 KMS 암호화 활성화 가능)

## Step 5. imagePullSecrets — 프라이빗 레지스트리 인증

```bash
kubectl create secret docker-registry regcred \
  --docker-server=ghcr.io --docker-username=myuser --docker-password=fake-token
kubectl get secret regcred -o jsonpath='{.type}'; echo
```

예상 출력:
```
kubernetes.io/dockerconfigjson      ← 특수 타입
```

사용법(참고): Pod spec에 `imagePullSecrets: [{name: regcred}]`.

> 💡 **EKS+ECR 조합에서는 이것이 필요 없습니다** — 노드 IAM 역할이 ECR 권한을 가지므로 자동 인증됩니다. imagePullSecrets는 ECR 밖(ghcr, Docker Hub 프라이빗 등)에서만.

## Step 6. RBAC 미리보기 — 누가 Secret을 읽을 수 있나

```bash
kubectl auth can-i get secrets                      # 나(관리자) → yes
kubectl auth can-i get secrets --as=system:serviceaccount:default:default
```

예상 출력:
```
yes
no        ← 기본 ServiceAccount는 Secret을 못 읽습니다 (다행!)
```

✅ 이 `no`를 유지하는 것이 Secret 보안의 핵심 — 모듈 11에서 "필요한 만큼만 yes로 여는" 법을 배웁니다.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| `CreateContainerConfigError` | 참조한 Secret 없음/key 오타 — describe로 확인 |
| Secret 값에 특수문자 깨짐 | 셸 인용 문제 — `--from-file` 또는 stringData 사용 |
| base64 결과에 줄바꿈 섞임 | `echo -n` 없이 인코딩한 값 — `echo -n 'pw' | base64` |

## 정리

```bash
bash cleanup.sh
```
