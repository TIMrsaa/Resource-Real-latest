# Lab 01 — 테넌트 패키지 조립과 격리 검증

## Step 1. 두 테넌트 생성

```bash
kubectl apply -f manifests/tenant-package.yaml          # team-rocket
# team-galaxy 복제 (sed로 이름 치환)
sed 's/team-rocket/team-galaxy/g' manifests/tenant-package.yaml | kubectl apply -f -
kubectl get ns -l tenant -L cost-center,pod-security.kubernetes.io/enforce
```

예상: 두 ns가 라벨/PSA와 함께. 각 ns에 Quota/LimitRange/NetworkPolicy가 딸려 왔는지:

```bash
kubectl get quota,limitrange,networkpolicy -n team-rocket
```

## Step 2. 격리 검증 매트릭스 — 각 부품이 일하는지

### ① RBAC: 남의 방 출입 차단

```bash
kubectl auth can-i get pods -n team-galaxy --as-group=team-rocket-devs --as=alice    # no
kubectl auth can-i get pods -n team-rocket --as-group=team-rocket-devs --as=alice    # yes
kubectl auth can-i create clusterroles --as-group=team-rocket-devs --as=alice        # no (escalation 방지)
```

✅ team-rocket 개발자는 자기 ns만, 클러스터 리소스는 손 못 댐.

### ② Quota: 독식 차단

```bash
# Quota(pods:30)를 넘겨보기
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hog
  namespace: team-rocket
  labels: { app: hog }
spec:
  replicas: 35                     # ← quota(pods:30)를 초과하는 요구
  selector:
    matchLabels: { app: hog }
  template:
    metadata:
      labels: { app: hog }
    spec:
      containers:
        - name: hog
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sleep", "600"]
EOF
sleep 5
kubectl get deploy hog -n team-rocket          # 30에서 막힘
kubectl describe rs -n team-rocket | grep -i forbidden | head -1
kubectl delete deployment hog -n team-rocket
```

✅ 한 팀이 클러스터 전체 Pod 슬롯을 독식 불가.

### ③ NetworkPolicy: 옆 팀 침범 차단 (모듈 09 실험의 재방문)

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: team-galaxy
  labels: { app: web }
spec:
  containers:
    - name: web
      image: registry.k8s.io/e2e-test-images/agnhost:2.53
      args: ["netexec", "--http-port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: team-galaxy
spec:
  selector: { app: web }
  ports:
    - port: 80
      targetPort: 8080
EOF
kubectl wait --for=condition=Ready pod/web -n team-galaxy

# team-rocket에서 team-galaxy의 web 침범 시도
kubectl run intruder -n team-rocket --rm -it --restart=Never \
  --image=public.ecr.aws/docker/library/busybox:stable --labels=team=ok \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":10001},"containers":[{"name":"intruder","image":"public.ecr.aws/docker/library/busybox:stable","command":["wget","-qO-","-T","3","http://web.team-galaxy/hostname"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
  || echo "BLOCKED — 옆 테넌트 접근 차단됨"
```

예상: timeout/BLOCKED — team-galaxy의 default-deny가 막았습니다. (intruder Pod가 PSA baseline을 통과하도록 securityContext를 갖춘 점도 주목 — 모듈 32)

### ④ PSA: privileged 차단

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: badpod
  namespace: team-rocket
  labels: { run: badpod }
spec:
  containers:
    - name: badpod
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "60"]
      securityContext:
        privileged: true          # ← PSA restricted가 거부해야 정상
EOF
```

예상: `Forbidden ... baseline ... privileged` — 노드 장악 시도 차단.

✅ **4개 부품이 각자 다른 공격 벡터를 막습니다** — 하나만 빼도 그 방향이 뚫린다는 것을 매트릭스로 확인.

## Step 3. 비용 가시화 흉내

```bash
# 테넌트별 Quota 사용률 (실무 청구서의 원천)
for ns in team-rocket team-galaxy; do
  echo "=== $ns ==="
  kubectl get quota tenant-quota -n $ns -o jsonpath='{range .status.used}{@}{end}' 2>/dev/null
  kubectl describe quota tenant-quota -n $ns | grep -A6 "Resource"
done
```

✅ cost-center 라벨 + Quota 사용량 = "쓴 만큼 보여주기"의 데이터. OpenCost(eks 파트 22)가 여기에 달러를 붙입니다.

## Step 4. Helm 차트화 과제 (산출물 진화)

이 패키지를 모듈 17의 방식으로 차트화하면: `helm install tenant ./tenant-chart --set tenant.name=team-X --set quota.cpu=8` 한 줄로 온보딩. 도전해보세요 — 멀티테넌시 + Helm의 종합 복습.

## 정리

team-galaxy의 web만 정리하고 ns는 lab-02에서 사용.
```bash
kubectl delete pod web -n team-galaxy --ignore-not-found; kubectl delete svc web -n team-galaxy --ignore-not-found
```
