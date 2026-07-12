# Lab 02 — 가비지 컬렉션, Finalizer, Server-Side Apply

## Part A. ownerReference와 GC

### Step 1. 손으로 부모-자식 관계 만들기 (컨트롤러 역할 체험)

```bash
# Website "blog"의 uid를 받아서, 자식 ConfigMap에 ownerReference로 심습니다
UID=$(kubectl get ws blog -o jsonpath='{.metadata.uid}')
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: blog-config
  ownerReferences:
  - apiVersion: platform.example.com/v1
    kind: Website
    name: blog
    uid: $UID
    controller: true
data: { theme: dark }
EOF
kubectl get cm blog-config -o jsonpath='{.metadata.ownerReferences[0].kind}'; echo
```

### Step 2. 부모 삭제 → 자식 자동 소멸

```bash
kubectl delete ws blog
sleep 3
kubectl get cm blog-config
```

예상 출력:
```
Error from server (NotFound): configmaps "blog-config" not found     ← GC가 치웠습니다!
```

✅ 컨트롤러들이 "자식 청소 코드"를 안 짜는 이유 — ownerReference만 심으면 GC가 해줍니다. (모듈 04에서 본 Deployment→RS→Pod 연쇄 삭제의 정체)

### Step 3. orphan — 자식 살리고 부모만

```bash
# 다시 만들고 (lab-01 Step 3 + Step 1 반복하거나 아래 한 번에)
kubectl apply -f - <<'EOF'
apiVersion: platform.example.com/v1
kind: Website
metadata: { name: blog }
spec: { image: "public.ecr.aws/nginx/nginx:1.27", replicas: 3 }
EOF
UID=$(kubectl get ws blog -o jsonpath='{.metadata.uid}')
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: blog-config
  ownerReferences: [{ apiVersion: platform.example.com/v1, kind: Website, name: blog, uid: $UID }]
data: { theme: dark }
EOF

kubectl delete ws blog --cascade=orphan
kubectl get cm blog-config -o jsonpath='{.metadata.ownerReferences}'; echo
```

예상: ConfigMap 생존 + ownerReferences가 **제거됨** (고아 처리). 컨트롤러 마이그레이션 때 "관리 객체를 살려둔 채 관리자만 교체"하는 기법.

## Part B. Finalizer

### Step 4. Terminating에 "일부러" 가두기

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: guarded
  finalizers: [example.com/manual-cleanup]
data: { important: data }
EOF

kubectl delete cm guarded --wait=false
kubectl get cm guarded -o jsonpath='{.metadata.deletionTimestamp}'; echo
kubectl get cm guarded
```

예상 출력:
```
2026-06-11T...        ← 삭제 "표시"만 됨
NAME      DATA   AGE
guarded   1      2m   ← 여전히 존재! (Terminating 상태)
```

✅ **모듈 09에서 봤던 "ns가 안 지워져요"의 축소판.** delete는 deletionTimestamp를 찍을 뿐, finalizer가 남아 있으면 보존됩니다.

### Step 5. 뒷정리 완료 선언 = finalizer 제거

```bash
# (실제라면 여기서 컨트롤러가 외부 자원을 정리한 뒤)
kubectl patch cm guarded --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]'
kubectl get cm guarded
```

예상: `NotFound` — finalizer가 비는 **순간** 진짜 삭제가 집행됐습니다.

> ⚠️ 방금 한 "수동 제거"는 실무에서 **뒷정리 포기 선언**입니다. ns가 Terminating에 갇혔을 때 순서: ① 어떤 리소스의 어떤 finalizer가 남았나 (`kubectl get ns X -o yaml`, 내부 리소스 조회) ② 그 finalizer 담당 컨트롤러가 살아있나/에러는 ③ 고칠 수 없을 때만 수동 제거 + 고아 자원 수동 정리.

## Part C. Server-Side Apply

### Step 6. 두 관리자의 필드 소유권

```bash
# team-a가 SSA로 Deployment 생성 (image와 replicas 소유)
cat > /tmp/team-a.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: ssa-demo }
spec:
  replicas: 2
  selector: { matchLabels: { app: ssa-demo } }
  template:
    metadata: { labels: { app: ssa-demo } }
    spec:
      containers:
      - name: app
        image: public.ecr.aws/nginx/nginx:1.27
EOF
kubectl apply --server-side --field-manager=team-a -f /tmp/team-a.yaml

# 소유권 장부 확인
kubectl get deploy ssa-demo -o jsonpath='{.metadata.managedFields[*].manager}'; echo
```

### Step 7. 남의 필드를 건드리면 — 명시적 conflict

```bash
# team-b가 replicas만 바꾸려 시도
cat > /tmp/team-b.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: ssa-demo }
spec:
  replicas: 5
EOF
kubectl apply --server-side --field-manager=team-b -f /tmp/team-b.yaml
```

예상 출력:
```
error: Apply failed with 1 conflict: conflict with "team-a": .spec.replicas
```

✅ **"누구 소유 필드인지"가 에러에 명시됩니다** — 모듈 21의 막연한 409와의 차이. 해소는 셋 중 하나:

```bash
# (a) 소유권 강탈 (의도가 확실할 때)
kubectl apply --server-side --field-manager=team-b --force-conflicts -f /tmp/team-b.yaml
# (b) team-a가 자기 manifest에서 replicas를 빼서 소유 포기 → team-b가 자연 인수
# (c) 설계 수정: replicas는 HPA가 소유하도록 양쪽 다 명시 안 함 (모듈 13/17의 결론!)
```

✅ "HPA 쓰면 YAML에서 replicas 빼라"(모듈 13)의 이론적 근거가 이 **소유권 모델**입니다.

## 정리

```bash
bash cleanup.sh
```
