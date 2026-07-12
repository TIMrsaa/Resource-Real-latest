# Lab 01 — RBAC: 거부에서 시작해 최소 권한까지

## Step 0. 준비

```bash
kubectl create namespace rbac-lab
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
  namespace: rbac-lab
  labels: { app: demo }
spec:
  replicas: 1
  selector:
    matchLabels: { app: demo }
  template:
    metadata:
      labels: { app: demo }
    spec:
      containers:
        - name: demo
          image: public.ecr.aws/nginx/nginx:1.27
EOF
```

## Step 1. 가상의 사용자로 "기본 거부" 확인

EKS에서 인증은 IAM이지만, **impersonation**으로 임의 신원을 흉내 내 RBAC만 순수하게 실험할 수 있습니다:

```bash
kubectl get pods -n rbac-lab --as=intern
```

예상 출력:
```
Error from server (Forbidden): pods is forbidden: User "intern" cannot list resource "pods" ...
```

✅ 어떤 Binding에도 안 걸리는 신원 = 전부 거부. **RBAC의 기본값은 0입니다.**

## Step 2. Role + RoleBinding으로 읽기 권한 부여

```bash
kubectl create role pod-reader -n rbac-lab \
  --verb=get,list,watch --resource=pods,pods/log
kubectl create rolebinding intern-reader -n rbac-lab \
  --role=pod-reader --user=intern

# 검증 (can-i = RBAC의 단위 테스트)
kubectl auth can-i list pods -n rbac-lab --as=intern        # yes
kubectl auth can-i delete pods -n rbac-lab --as=intern      # no
kubectl auth can-i list pods -n default --as=intern         # no (ns 밖!)
kubectl get pods -n rbac-lab --as=intern                    # 실제로 됨
```

✅ 허용은 **준 것만, 준 곳에서만**. 3개의 can-i 결과가 그 증명입니다.

## Step 3. 함정 체험 — exec는 read가 아닙니다

```bash
kubectl auth can-i create pods/exec -n rbac-lab --as=intern   # no
POD=$(kubectl get pod -n rbac-lab -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n rbac-lab $POD --as=intern -- ls 2>&1 | head -1
```

예상: Forbidden. **"읽기 권한만 줬는데 셸 접속이 되네?" 사고를 막는 지식**: exec는 `pods/exec`의 **create**입니다. 반대로 말하면, 누군가에게 exec를 주는 것은 그 Pod의 SA 권한을 통째로 주는 것과 같습니다(토큰 탈취 가능).

## Step 4. ClusterRole + RoleBinding — 실무 표준 조합

```bash
# 내장 ClusterRole "view"를 rbac-lab 한 곳에만 적용
kubectl create rolebinding intern-view -n rbac-lab \
  --clusterrole=view --user=intern

kubectl auth can-i list deployments -n rbac-lab --as=intern   # yes (view 덕)
kubectl auth can-i list secrets -n rbac-lab --as=intern       # no!
```

✅ **view에는 secrets가 빠져 있습니다** — 모듈 07의 "Secret 보호의 본체는 RBAC"가 내장 Role에도 반영된 것. 권한 설계 시 본보기로 삼아라:

```bash
kubectl get clusterrole view -o yaml | grep -B2 -A5 "secrets" | head -10   # 정말 없는지 직접 확인
```

## Step 5. 그룹 바인딩 — 사람 단위 운영의 종말

```bash
kubectl create rolebinding dev-team-edit -n rbac-lab \
  --clusterrole=edit --group=dev-team

kubectl auth can-i create deployments -n rbac-lab \
  --as=anyone --as-group=dev-team        # yes — 그룹 소속이면 누구든
```

실무 운영: 사람 ↔ 그룹 매핑은 IdP/IAM에서, 그룹 ↔ 권한은 K8s에서. 입퇴사 처리가 IAM에서 끝납니다 (lab-02에서 EKS 버전).

## Step 6. 전체 권한 목록 감사

```bash
kubectl auth can-i --list -n rbac-lab --as=intern
```

예상 출력: pod-reader + view의 합집합이 표로. 정기 감사에서 "이 신원이 가진 모든 것"을 볼 때 씁니다.

## 정리

rbac-lab ns는 lab-02에서 계속 사용.
