# Lab 02 — ServiceAccount(Pod의 권한)와 EKS Access Entries

## Part A. ServiceAccount

### Step 1. Pod가 API 서버를 호출할 수 있을까 (default SA)

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: api-caller
  namespace: rbac-lab
  labels: { run: api-caller }
spec:
  containers:
    - name: api-caller
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/api-caller -n rbac-lab

kubectl exec -n rbac-lab api-caller -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
wget -qO- --no-check-certificate \
  --header="Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/rbac-lab/pods 2>&1 | head -5'
```

예상 출력:
```
{"kind":"Status", ... "message":"pods is forbidden: User \"system:serviceaccount:rbac-lab:default\" cannot list ..."}
```

✅ 두 가지 발견: ① 모든 Pod에 **토큰이 자동 마운트**되어 있고 ② default SA는 **인증은 되지만 인가에서 거부**됩니다 (403 ≠ 401). 이 "거부"가 깨지면(누가 default에 권한을 주면) 모든 Pod가 그 권한을 갖습니다 — 함정 1순위.

### Step 2. 전용 SA + 최소 권한

```bash
kubectl create serviceaccount pod-lister -n rbac-lab
kubectl create rolebinding pod-lister-rb -n rbac-lab \
  --role=pod-reader --serviceaccount=rbac-lab:pod-lister

# SA를 쓰는 Pod로 교체
kubectl delete pod api-caller -n rbac-lab
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: api-caller
  namespace: rbac-lab
  labels: { run: api-caller }
spec:
  serviceAccountName: pod-lister
  containers:
    - name: api-caller
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/api-caller -n rbac-lab

kubectl exec -n rbac-lab api-caller -- sh -c '
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
wget -qO- --no-check-certificate --header="Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/rbac-lab/pods 2>/dev/null | grep -m1 "\"name\""'
```

예상 출력: Pod 이름이 담긴 JSON — **인가 통과.** "앱이 K8s API를 쓰려면: 전용 SA + 필요한 동사만"의 완성형입니다 (Operator 개발의 기초 — 모듈 30).

### Step 3. 토큰이 필요 없는 앱은 마운트 끄기

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: no-token
  namespace: rbac-lab
  labels: { run: no-token }
spec:
  automountServiceAccountToken: false
  containers:
    - name: no-token
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
EOF
kubectl exec -n rbac-lab no-token -- ls /var/run/secrets/kubernetes.io/serviceaccount 2>&1
```

예상: `No such file or directory` — 탈취당해도 내줄 토큰이 없습니다. K8s API를 안 쓰는 일반 웹앱의 권장 설정.

## Part B. EKS Access Entries — IAM과 RBAC의 연결

### Step 4. 내 신원이 어떻게 매핑되는지 보기

```bash
kubectl auth whoami
```

예상 출력 (발췌):
```
Username: arn:aws:iam::123456789012:user/me      (또는 assumed-role/...)
Groups:   [system:masters ...]                   ← 클러스터 생성자는 admin
```

```bash
# 이 매핑의 관리 주체 = access entries
aws eks list-access-entries --cluster-name k8s-study --region ap-northeast-2
```

### Step 5. 동료에게 "읽기 전용" 클러스터 권한 주기 (시나리오)

실제 IAM 사용자가 없어도 흐름을 알아두자 — EKS 운영의 핵심 절차입니다:

```bash
# ① access entry 생성: IAM ARN을 클러스터에 등록
aws eks create-access-entry --cluster-name k8s-study --region ap-northeast-2 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:user/teammate \
  --kubernetes-groups viewers          # ← K8s 그룹 이름으로 매핑

# ② 그 그룹에 RBAC 바인딩 (이건 K8s 쪽)
kubectl create clusterrolebinding viewers-binding \
  --clusterrole=view --group=viewers
```

또는 RBAC 없이 AWS 관리형 정책으로 끝내는 방법:

```bash
aws eks associate-access-policy --cluster-name k8s-study --region ap-northeast-2 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:user/teammate \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=cluster
```

> 💡 정리: **인증=IAM, 인가=RBAC(또는 EKS access policies).** "사용자 추가"는 K8s 객체 생성이 아니라 IAM+access entry 작업입니다. 옛 문서의 aws-auth ConfigMap 편집은 이제 쓰지 않습니다.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| `Unauthorized` (401) | 인증 실패 — IAM 자격증명/SSO 세션 (`aws sts get-caller-identity`) |
| `Forbidden` (403) | 인증은 됨, 인가 실패 — RBAC/access policy 확인 (`auth can-i --list`) |
| SA 토큰으로 호출 시 401 | 토큰 만료(1h) — 파일을 다시 읽으면 갱신된 토큰 |

## 정리

```bash
bash cleanup.sh
```
