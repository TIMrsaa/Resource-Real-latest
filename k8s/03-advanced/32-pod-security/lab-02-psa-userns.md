# Lab 02 — PSA 적용과 user namespaces

## Step 1. PSA 라벨 — 운영 정석 조합

```bash
kubectl create ns secure-zone
kubectl label ns secure-zone \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

## Step 2. baseline 강제 확인 — privileged 거부

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: hacker
  namespace: secure-zone
  labels: { run: hacker }
spec:
  containers:
    - name: hacker
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      securityContext:
        privileged: true          # ← restricted 프로파일이 거부해야 정상
EOF
```

예상 출력:
```
Error from server (Forbidden): pods "hacker" is forbidden: violates PodSecurity "baseline:latest":
privileged (container "hacker" must not set securityContext.privileged=true)
```

✅ **무엇이 왜 거부됐는지 필드 단위로** 알려줍니다. hostPath/hostNetwork도 시도해보세요 — 전부 baseline이 막습니다 (모듈 08에서 "위험물"이라 한 hostPath의 공식 차단).

## Step 3. warn 모드 — restricted 준비도 측정

```bash
kubectl run plain -n secure-zone --image=public.ecr.aws/docker/library/busybox:stable -- sleep 600
```

예상 출력:
```
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false,
unrestricted capabilities, runAsNonRoot != true, seccompProfile ...
pod/plain created          ← baseline은 통과라 생성은 됨
```

✅ **경고 목록이 곧 "restricted로 가기 위한 할 일 목록"입니다.** lab-01의 모범 템플릿을 적용한 Pod는:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: secure
  namespace: secure-zone
  labels: { run: secure }
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: secure
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF
```

예상: **경고 없이** 생성 — restricted 준비 완료.

## Step 4. enforce 승격 — 무중단 강화 절차

```bash
# 기존 Pod는 그대로, "새 Pod"부터 restricted 강제
kubectl label ns secure-zone pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl get pods -n secure-zone      # plain이 여전히 Running (소급 적용 없음!)
kubectl delete pod plain -n secure-zone
kubectl run plain -n secure-zone --image=public.ecr.aws/docker/library/busybox:stable -- sleep 600
```

예상: 이번엔 **Forbidden** — 재생성부터 막힙니다. PSA는 기존 Pod를 죽이지 않으므로(소급 없음) 승격이 무중단입니다. 단, 그래서 "라벨 붙였으니 안전"이 아니라 **기존 위반 Pod의 점진 교체까지가 강화 작업**입니다.

## Step 5. user namespaces — 탈출해도 일반 유저

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: userns, namespace: secure-zone }
spec:
  hostUsers: false                  # ★ user namespace 분리
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: { type: RuntimeDefault }
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:stable
    command: ["sleep", "600"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: { drop: ["ALL"] }
EOF
kubectl wait --for=condition=Ready pod/userns -n secure-zone --timeout=60s
```

검증 — 컨테이너 안과 호스트의 uid 비교:

```bash
kubectl exec -n secure-zone userns -- sh -c 'id -u; cat /proc/self/uid_map'
```

예상 출력:
```
10001
         0     165536      65536      ← 컨테이너 uid 0 ↔ 호스트 uid 165536 매핑!
```

```bash
# 노드에서 실제 프로세스의 호스트 uid 확인 (모듈 26 기술)
NODE=$(kubectl get pod userns -n secure-zone -o jsonpath='{.spec.nodeName}')
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable -- \
  chroot /host sh -c 'ps -eo user,uid,comm | grep sleep | head -2'
```

예상: sleep 프로세스의 호스트 uid가 **175537(165536+10001) 같은 고유 대역** — 컨테이너가 root였더라도 호스트에선 의미 없는 번호입니다.

✅ **모듈 01에서 "컨테이너 root = 호스트 root(USER ns 안 쓰면)"이라 경고했던 그 구멍이 닫혔습니다.** 탈출 성공 시나리오의 피해가 "호스트 장악"에서 "비특권 유저의 발버둥"으로 축소.

> 호환성 메모: hostUsers: false는 일부 볼륨/기능과 제약이 있을 수 있습니다 — 신규 워크로드부터 적용하며 검증하는 접근을 권장.

## Step 6. 시스템 ns들의 PSA 상태 구경 (왜 전부 restricted가 아닌가)

```bash
kubectl get ns -L pod-security.kubernetes.io/enforce | head
```

kube-system은 privileged입니다 — CNI/CSI(모듈 27, 08)가 진짜 특권이 필요하니까. **"특권의 필요"가 ns 경계로 격리**되어 있는 구조를 확인하세요. 일반 워크로드 ns가 privileged라면 그것이 발견 사항입니다.

## 정리

```bash
bash cleanup.sh
```
